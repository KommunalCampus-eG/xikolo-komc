# frozen_string_literal: true

module XMLImporter
  require 'xml_importer/quiz'

  class SchemaError < StandardError
    attr_reader :errors

    def initialize(errors)
      errors = Array(errors)
      super("There are schema errors: #{errors.join(', ')}")
      @errors = errors
    end
  end

  class ParameterError < StandardError
    attr_reader :errors

    def initialize(errors)
      errors = Array(errors)
      super("There are parameter errors: #{errors.join(', ')}")
      @errors = errors
    end
  end
end
