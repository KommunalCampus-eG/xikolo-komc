# frozen_string_literal: true

require 'multi_process'
require 'pathname'
require 'active_support'
require 'active_support/core_ext'
require 'restify'
require 'pry'
require 'mkmf'
require 'net/http'
require 'aws-sdk-s3'

ChildProcess.posix_spawn = true

S3_STORAGE_DIR = Pathname.new "/tmp/xikolo-#{ENV.fetch('RAILS_ENV', 'integration')}-s3"

class Server < MultiProcess::Process
  include MultiProcess::Process::Rails

  attr_reader :id, :roles, :repo, :address

  def initialize(id, opts = {})
    @id    = id
    @name  = opts[:name]
    @roles = Array(opts[:roles]).compact
    @repo  = opts[:repo] || "xikolo/#{@name}"
    @port  = opts[:port]

    @address = '127.0.0.1'

    self.server = 'puma'

    dir = ::File.join(Server.base, opts.fetch(:subpath))
    env = {
      'RAILS_ENV' => 'integration',
      'GURKE' => 'true',
    }

    super(dir:, env:, title: id.to_s)
  end

  def server_command
    cmd = %w[ruby]
    cmd << '-S' << 'bundle' << 'exec' << 'puma'
    cmd << '--workers' << '0' << '--threads' << '3'
    cmd << '--bind' << "tcp://#{address}:#{port}"
    cmd
  end

  def bundle(task, *cmd)
    opts = cmd.last.is_a?(Hash) ? cmd.pop : {}

    args = []
    opts.slice(:path, :without).compact.each do |key, value|
      args << "--#{key}" << value.to_s
    end

    process 'ruby', '-S', 'bundle', task.to_s, *cmd, *args, opts
  end

  def process(*command)
    opts = command.last.is_a?(Hash) ? command.pop : {}
    opts = opts.merge(dir:, title: id)
    command.map!(&:to_s)

    MultiProcess::Process.new(*command, opts)
  end

  def file(*path)
    dir.join(*path.flatten)
  end

  def dir
    ::Pathname.new super
  end

  def available?
    if @last_avil_time.nil? || (Time.current - @last_avil_time) > 5
      @last_avil_time = Time.current
      receiver.message self, :sys, "Waiting for server on #{port}..."
    end

    super
  end

  def url(string = '/')
    "http://#{address}:#{port}#{string}"
  end

  def api
    @restify ||= Restify.new(url).get.value! # rubocop:disable Naming/MemoizedInstanceVariableName
  end

  class << self
    attr_writer :base

    def base
      @base ||= '..'
    end

    def required_roles
      @required_roles ||= []
    end

    def logger
      @logger ||= Logger.new sys: true, collapse: false
    end

    def group
      @group ||= MultiProcess::Group.new receiver: logger
    end

    def delayed_group
      @delayed_group ||= MultiProcess::Group.new receiver: logger
    end

    def sidekiq_group
      @sidekiq_group ||= MultiProcess::Group.new receiver: logger
    end

    def utils_group
      @utils_group ||= MultiProcess::Group.new receiver: logger
    end

    def util(key)
      utils_group.processes.find {|util| util.id == key }
    end

    def add(*args)
      opts = args.extract_options!

      # Ignore services that lack the required roles
      return if (required_roles - opts[:roles]).any?

      server = Server.new(*args, opts.merge(port: next_port))
      delayed_group << DelayedProcess.new(*args, opts) if server.roles.include? :delayed
      sidekiq_group << SidekiqProcess.new(*args, opts) if server.roles.include? :sidekiq
      group << server
    end

    def [](key)
      group.processes.find {|srv| srv.id == key }
    end

    def next_port
      @next_port ||= 8000 - 1
      @next_port += 1
    end

    def list(*roles)
      if roles.empty?
        group.processes
      else
        group.processes.select do |app|
          roles.all? {|role| app.roles.include? role }
        end
      end
    end

    def each(*roles, &)
      list(*roles).each(&)
    end

    def rake_log
      @rake_log ||= File.open('rake.log', 'w')
    end

    def exec(*roles, &)
      opts = roles.last.is_a?(Hash) ? roles.pop : {}
      unless opts.key? :receiver
        opts = opts.merge receiver: MultiProcess::Logger.new($stdout, $stderr,
          sys: opts.fetch(:sys, true))
      end
      opts = opts.merge partition: 2 if ENV['TEAMCITY_VERSION'] && !opts[:partition]

      timout = opts.delete(:timeout) || 240

      group = MultiProcess::Group.new(**opts)
      group << list(*roles).map(&).compact
      group.run!(delay: (opts[:delay] ? Float(opts[:delay]) : 0.5), timeout: timout)
    end

    def start
      if ENV['TEAMCITY_VERSION']
        group.start delay: 0.5
        delayed_group.start delay: 0.5
        sidekiq_group.start delay: 0.5
        group.available! timeout: 240
      else
        group.start delay: 0.1
        delayed_group.start delay: 0.1
        sidekiq_group.start delay: 0.1
        group.available! # default timeout
      end
    end

    def config_all
      $stdout.puts '(~)> Pre-init configuration...'
      $stdout.flush

      config_initializers
      config_services
      config_service_urls
      config_s3

      # Adjust simplecov coverage results from unit tests to have correct file names
      adjust_coverage_results if ENV['TEAMCITY_VERSION']
    end

    def config_initializers
      Server.each do |app|
        base = app.dir.join('config', 'initializers')
        base.mkpath

        Dir[base.join('integration*.rb')].each {|f| File.unlink f }
        FileUtils.ln_s Gurke.root.join('support/lib/initializers/integration.rb'), base
      end

      %i[config main msgr sidekiq].each do |type|
        Server.each(type) do |app|
          FileUtils.ln_s Gurke.root.join("support/lib/initializers/integration_#{type}.rb"),
            app.dir.join('config', 'initializers')
        end
      end
    end

    def config_services
      # A few services need special setup for integration tests
      %i[web account]
        .filter_map {|type| Server[type] }
        .each do |app|
          FileUtils.ln_s Gurke.root.join("support/lib/initializers/integration_#{app.id}.rb"),
            app.dir.join('config', 'initializers', "integration_x#{app.id}.rb")
        end
    end

    def config_service_urls
      Server.each do |app|
        File.write app.file('config/services.integration.yml'), YAML.dump(services_config)
      end
    end

    def config_s3
      conf = YAML.load_file(Gurke.root.join('support/lib/xikolo.yml').to_s)
      conf['domain'] = BASE_URI.host
      conf['domain'] += ":#{BASE_URI.port}" if BASE_URI.port
      conf['base_url'] = BASE_URI.to_s

      if ENV['S3_CONFIG_FILE']
        s3_config = YAML.safe_load_file(ENV['S3_CONFIG_FILE'])
        Xikolo.config['s3'] = s3_config['web']
        # already build resource object (the credentials might be overwritten
        # later on)
        Xikolo::S3.resource
      end

      Server.each :config do |app|
        dest = app.file('config', 'xikolo.integration.yml')
        dest.unlink if dest.exist?
        if s3_config
          conf.delete('s3')
          conf['s3'] = s3_config[app.id.to_s] if s3_config.key? app.id.to_s
        end
        dest.write YAML.dump conf
      end
    end

    def adjust_coverage_results
      Server.each do |app|
        resultfile = app.file('coverage', '.resultset.json')
        next unless resultfile.exist?

        system 'sed',
          '--in-place',
          "--expression=s|/var/lib/teamcity-agent/work/[^/]*/|#{File.realpath(app.dir)}/|",
          app.file('coverage', '.resultset.json').to_s
      end
    end

    def start_all
      $stdout.puts '(~)> Starting utilies...'
      $stdout.flush

      # start helper processes like minio (for S3 API)
      utils_group.start
      utils_group.available!

      $stdout.puts '(~)> Utilities started.'
      $stdout.flush

      config_all
      Server.util(:minio)&.setup

      $stdout.puts '(~)> Starting applications...'
      $stdout.flush

      Server.each do |app|
        Rack::Remote.add app.id.to_sym, url: "http://127.0.0.1:#{app.port}/__rack_remote_rpc__"
      end
      Server.start

      $stdout.puts '(~)> Applications started.'
      $stdout.flush
    end

    def stop_all
      processes = [utils_group, delayed_group, sidekiq_group].flat_map(&:processes)

      $stdout.puts '(~)> Stopping processes ...'
      processes.each do |app|
        ::Process.kill 'QUIT', app.childprocess.pid
      end
      Server.each do |app|
        ::Process.kill 'QUIT', app.childprocess.pid
      end
      sleep 2

      $stdout.puts '(~)> Killing processes ...'
      Server.each(&:stop)
      processes.each(&:stop)

      Server.each do |app|
        Dir[app.dir.join('config/initializers/integration*.rb')].each {|f| File.unlink f }
      end

      $stdout.puts '(~)> Application stopped.'
      $stdout.flush

      FileUtils.rmtree S3_STORAGE_DIR.to_s if S3_STORAGE_DIR.to_s.starts_with? '/tmp'
    end
  end

  class Logger < MultiProcess::Logger
    def initialize(*args)
      super

      @tests = {}
      @files = {}
    end

    def received(process, name, message)
      if (file = file_handle_for(process))
        file.puts "#{stream_symbol(name)} #{message.gsub(/\033.*?m/, '')}"
        file.flush
      end

      return if name == :out

      super
    end

    def stream_symbol(name)
      {sys: '$', out: '|', err: 'E'}[name] || '?'
    end

    def file_handle_for(process)
      @files[process] ||= begin
        FileUtils.mkdir_p 'log'
        File.open "log/#{process.title}.log", 'w'
      end
    end
  end
end

class DelayedProcess < Server
  def server_command
    cmd = %w[ruby]
    cmd << '-S' << 'bundle' << 'exec' << 'rake' << 'delayed:work'
    cmd
  end
end

class SidekiqProcess < Server
  def server_command
    cmd = %w[ruby]
    cmd << '-S' << 'bundle' << 'exec' << 'sidekiq'
    cmd << '--verbose'
    cmd << '--env' << 'integration'
    cmd
  end
end

class MinioProcess < MultiProcess::Process
  def initialize
    super(*server_command, title: 'minio')
  end

  def id
    :minio
  end

  def server_command
    cmd = %w[minio server]
    cmd << '--address' << '127.0.0.1:8099'
    cmd << '--config-dir' << File.expand_path('../../../tmp/.minio', __dir__)
    cmd << '--quiet'
    cmd << S3_STORAGE_DIR.to_s
    cmd
  end

  def url
    'http://127.0.0.1:8099'
  end

  def available?
    return false unless alive?

    Typhoeus.get(url).code == 403
  rescue StandardError
    false
  end

  def setup
    self.class.setup
  end

  def self.delete_all
    Xikolo::S3.resource.buckets.each do |bucket|
      # First, delete all objects inside the bucket
      bucket.objects.each(&:delete)

      # Then, delete the empty bucket
      bucket.delete
    end
  end

  def self.setup
    uploads = Xikolo::S3.resource.bucket 'xikolo-uploads'
    uploads.create unless uploads.exists?
    uploads.policy.put policy: JSON.dump(YAML.safe_load(<<~POLICY))
      Id: uploads
      Version: '2012-10-17'
      Statement:
        - Sid: content
          Action:
            - 's3:GetObject'
            - 's3:DeleteObject'
          Effect: Allow
          Resource:
            - 'arn:aws:s3:::xikolo-uploads/*'
          Principal: {'AWS': '*'}
    POLICY

    xipublic = Xikolo::S3.resource.bucket 'xikolo-public'
    xipublic.create unless xipublic.exists?
    xipublic.policy.put policy: JSON.dump(YAML.safe_load(<<~POLICY))
      Id: public
      Version: '2012-10-17'
      Statement:
        - Sid: content
          Action:
            - 's3:GetObject'
          Effect: Allow
          Resource:
            - 'arn:aws:s3:::xikolo-public/*'
          Principal: {'AWS': '*'}
    POLICY

    certificates = Xikolo::S3.resource.bucket 'xikolo-certificate'
    certificates.create unless certificates.exists?

    collab = Xikolo::S3.resource.bucket 'xikolo-collabspace'
    collab.create unless collab.exists?
    collab.policy.put policy: JSON.dump(YAML.safe_load(<<~POLICY))
      Id: collabspace
      Version: '2012-10-17'
      Statement:
        - Sid: content
          Action:
            - 's3:GetObject'
          Effect: Allow
          Resource:
            - 'arn:aws:s3:::xikolo-collabspace/collabspaces/*'
          Principal: {'AWS': '*'}
    POLICY

    pas = Xikolo::S3.resource.bucket 'xikolo-peerassessment'
    pas.create unless pas.exists?
    pas.policy.put policy: JSON.dump(YAML.safe_load(<<~POLICY))
      Id: peerassessment
      Version: '2012-10-17'
      Statement:
        - Sid: content
          Action:
            - 's3:GetObject'
          Effect: Allow
          Resource:
            - 'arn:aws:s3:::xikolo-peerassessment/assessments/*/attachments/*'
          Principal: {'AWS': '*'}
    POLICY

    pinboard = Xikolo::S3.resource.bucket 'xikolo-pinboard'
    pinboard.create unless pinboard.exists?
    pinboard.policy.put policy: JSON.dump(YAML.safe_load(<<~POLICY))
      Id: pinboard
      Version: '2012-10-17'
      Statement:
        - Sid: content
          Action:
            - 's3:GetObject'
          Effect: Allow
          Resource:
            - 'arn:aws:s3:::xikolo-pinboard/courses/*'
          Principal: {'AWS': '*'}
    POLICY

    scientist = Xikolo::S3.resource.bucket 'xikolo-scientist'
    scientist.create unless scientist.exists?
    scientist.policy.put policy: JSON.dump(YAML.safe_load(<<~POLICY))
      Id: scientist
      Version: '2012-10-17'
      Statement:
        - Sid: content
          Action:
            - 's3:PutObject'
          Effect: Allow
          Resource:
            - 'arn:aws:s3:::xikolo-scientist/experiments/*'
          Principal: {'AWS': '*'}
    POLICY

    video = Xikolo::S3.resource.bucket 'xikolo-video'
    video.create unless video.exists?
    video.policy.put policy: JSON.dump(YAML.safe_load(<<~POLICY))
      Id: video
      Version: '2012-10-17'
      Statement:
        - Sid: content
          Action:
            - 's3:GetObject'
          Effect: Allow
          Resource:
            - 'arn:aws:s3:::xikolo-video/*'
          Principal: {'AWS': '*'}
    POLICY
  end
end

Server.utils_group << MinioProcess.new if !ENV['S3_CONFIG_FILE'] && find_executable('minio')
