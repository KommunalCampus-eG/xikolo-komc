# frozen_string_literal: true

module Bridges
  module MoocHub
    # rubocop:disable Rails/ApplicationController
    class CoursesController < ActionController::Base
      include MarkdownHelper

      before_action do
        raise AbstractController::ActionNotFound unless api_config&.dig('enabled')
      end

      ALLOWED_ORG_KEYS  = %w[name identifier type description image].freeze
      REQUIRED_ORG_KEYS = %w[name identifier].freeze
      ALLOWED_IMG_KEYS  = %w[description type contentUrl license].freeze
      REQUIRED_IMG_KEYS = %w[contentUrl license].freeze

      def index
        version = negotiate_versions.assign_version(requested_version)

        unless version
          render(
            content_type: 'application/problem+json',
            json: {
              title: 'Unsupported version requested',
              status: Rack::Utils.status_code(:not_acceptable),
            },
            status: :not_acceptable
          )
          return
        end

        response.set_header('Sunset', version.expiry_date.httpdate) if version.expires?

        serialization_method = serialization_method(version)

        render json: {
          links:,
          data: courses.map(&method(serialization_method)),
        }, content_type: "application/vnd.api+json; moochub-version=#{version}"
      end

      private

      def requested_version
        @requested_version ||= begin
          accept_header = request.headers['Accept']
          matches = /; ?moochub-version=(.+)$/.match accept_header.to_s

          matches[1] if matches
        end
      end

      # The order within the hash is crucial
      # as the first element is used as the default value, regardless of its version number.
      def version_serialization_mapping
        @version_serialization_mapping ||= {
          Versioning::Version.new('3.0') => :serialize_course,
        }
      end

      def supported_versions
        version_serialization_mapping.keys
      end

      def negotiate_versions
        Versioning::Negotiation.new(
          supported_versions
        )
      end

      def courses
        @courses ||= course_api
          .rel(:courses)
          .get(
            {
              public: true,
              exclude_external: true,
              hidden: false,
              alphabetic: true,
              page:,
              active_after: 3.years.ago.to_date.iso8601,
            }
          ).value!
      end

      def page
        @page ||= [params[:page].to_i, 1].max
      end

      def links
        {
          self: bridges_moochub_courses_url(page: courses.response.headers['X_CURRENT_PAGE'].to_i),
          first: bridges_moochub_courses_url(page: 1),
          last: bridges_moochub_courses_url(page: courses.response.headers['X_TOTAL_PAGES'].to_i),
          prev: rel_prev,
          next: rel_next,
        }.compact
      end

      def rel_next
        @rel_next ||= bridges_moochub_courses_url(page: page + 1) if courses.rel?(:next)
      end

      def rel_prev
        @rel_prev ||= bridges_moochub_courses_url(page: page - 1) if courses.rel?(:prev)
      end

      def serialization_method(version)
        version_serialization_mapping[version]
      end

      def serialize_course(course)
        {
          id: course['id'],
          type: 'Course',
          attributes: attrs_for(course).merge(
            startDate: Array.wrap(course['start_date']),
            endDate: Array.wrap(course['end_date']),
            trailer: teaser_data_for(course),
            courseMode: ['online'],
            inLanguage: [course['lang']],
            image: image_data_for(course),
            offers: offers_for(course),
            keywords: keywords_for(course),
            teaches: skills_for(course),
            educationalAlignment: educational_alignment_for(course),
            publisher: organization,
            creator: creator_for(course),
            license: licenses_for(course),
            learningResourceType: {
              identifier: 'https://w3id.org/kim/hcrt/course',
              type: 'Concept',
              inScheme: 'https://w3id.org/kim/hcrt/scheme',
            }
          ).compact,
        }
      end

      def attrs_for(course)
        {
          name: course['title'],
          courseCode: course['course_code'],
          # Both the abstract and description are converted to HTML.
          abstract: render_markdown(course['abstract']).presence,
          description: render_markdown(course['abstract']).presence,
          startDate: course['start_date'],
          endDate: course['end_date'],
          # Courses are available as self-paced courses once they ended,
          # and are not planned to be removed from the platform in advance
          availableUntil: nil,
          image: image_data_for(course),
          instructors: instructors_for(course),
          learningObjectives: course['learning_goals'],
          duration: duration_for(course),
          # As the workload is not available as structured data,
          # it's omitted for now.
          workload: nil,
          partnerInstitute: [],
          moocProvider: provider,
          access: access_for(course),
          url: PublicCoursePage.url_for(course),
        }
      end

      def organization
        org = api_config.dig('course_metadata', 'organization')

        return if org.blank?
        # TODO: We might want to add a fallback if the required values are missing.
        return if REQUIRED_ORG_KEYS.intersection(org.keys) != REQUIRED_ORG_KEYS

        img = api_config.dig('course_metadata', 'organization', 'image')
        return if img.present? &&
                  (REQUIRED_IMG_KEYS.intersection(img.keys) != REQUIRED_IMG_KEYS)

        # Filter and compact image attributes (if applicable)
        org['image'] = img.slice(*ALLOWED_IMG_KEYS).compact if img.present?

        # Return filtered organization attributes
        # TODO: we might want to add a fallback if the result is empty.
        org.slice(*ALLOWED_ORG_KEYS).compact
      end

      def creator_for(course)
        Rails.cache.fetch(
          "bridges/mooc_hub/creator/#{course['id']}",
          expires_in: 1.hour,
          race_condition_ttl: 1.minute
        ) do
          if course['teacher_ids'].any?
            course_api.rel(:teachers).get({course: course['id']}).then do |teachers|
              # Return an array with the prefix and the actual name, e.g.
              # ['Prof. Dr.', 'Mustermann'] for 'Prof. Dr. Mustermann'.
              regex = /((?>Prof\.[[:blank:]]?)?(?>(?:PD)?[[:blank:]]?)?(?>Dr\.(?>-Ing\.)?[[:blank:]]?)*)(.*)/

              # Courses may have multiple teachers, so we return an array of JSON objects.
              teachers.filter_map do |teacher|
                split_name = teacher['name'].split(regex).compact_blank.map(&:strip)

                {
                  name: split_name[-1],
                  honorificPrefix: split_name[-2],
                  type: 'Person',
                  description: I18n.with_locale(course['lang'].to_sym) do
                    Translations.new(teacher['description']).to_s
                  end,
                }.tap do |creator|
                  if teacher['picture_url'].present?
                    creator[:image] = {
                      type: 'ImageObject',
                      contentUrl: teacher['picture_url'],
                      license: api_config.dig('course_metadata', 'creator', 'license'),
                    }
                  end
                end
              end
            end.value!
          else
            Array.wrap(organization)
          end
        end
      end

      def image_data_for(course)
        visual = course_visuals[course['id']]

        if visual&.image_url
          {
            type: 'ImageObject',
            contentUrl: visual.image_url,
            license: licenses_for(course),
          }
        else
          {
            type: 'ImageObject',
            contentUrl: Xikolo.base_url.join(helpers.asset_url('defaults/course.png')),
            license: [{
              identifier: 'CC0-1.0',
              url: 'https://creativecommons.org/publicdomain/zero/1.0',
              contentUrl: nil,
            }],
          }
        end
      end

      def teaser_data_for(course)
        visual = course_visuals[course['id']]
        return unless visual&.video_stream

        {
          type: 'VideoObject',
          contentUrl: visual.video_stream.hd_url.presence || visual.video_stream.sd_url,
          license: licenses_for(course),
        }
      end

      def course_visuals
        @course_visuals ||= ::Course::Visual.where(course_id: courses.pluck('id'))
          .index_by(&:course_id)
      end

      def instructors_for(course)
        # Include teacher name only, omit image and description.
        course['teacher_text']&.split(',')&.map {|name| {name: name.strip} } || []
      end

      def keywords_for(course)
        return [] if course['classifiers'].blank?

        Catalog::Course.find(course['id']).classifiers('keywords')
      end

      def duration_for(course)
        return if course['start_date'].blank? || course['end_date'].blank?

        diff = Time.zone.parse(course['end_date']) - Time.zone.parse(course['start_date'])
        ActiveSupport::Duration.build(diff).tap do |duration|
          # Limit duration to the given parts,
          # do not include hours, minutes, and seconds.
          duration.parts.slice!(:years, :months, :weeks, :days)
        end.iso8601
      end

      def skills_for(course)
        Course::Metadata.resolve(course['id'], Course::Metadata::TYPE::SKILLS, Course::Metadata::VERSION)
      end

      def educational_alignment_for(course)
        Course::Metadata.resolve(course['id'], Course::Metadata::TYPE::EDUCATIONAL_ALIGNMENT, Course::Metadata::VERSION)
      end

      def provider
        @provider ||= {
          name: Xikolo.config.site_name,
          url: root_url,
          logo: provider_logo,
        }
      end

      def provider_logo
        @provider_logo ||= view_context.image_url(
          "#{I18n.t(:'header.logo', default: 'logo', fallback: false)}.png"
        )
      end

      ##
      # The course license can be provided per course. If it is not available,
      # fall back to the platform's default course license. When not configured,
      # indicate a proprietary license to be safe.
      #
      # @param course [Restify::Resource]
      def licenses_for(course)
        if Course::Course.find(course['id']).license.present?
          Course::Course.find(course['id']).license.data
        elsif (license = api_config.dig('course_license', 'default'))
          [
            {
              identifier: license['id'],
              url: license['url'],
              contentUrl: nil,
            },
          ]
        else
          [
            {
              identifier: 'proprietary',
              url: nil,
              contentUrl: nil,
            },
          ]
        end
      end

      def access_for(course)
        return %w[free] unless paid?(course)

        %w[paid]
      end

      def offers_for(course)
        Course::Course.find(course['id']).offers.map do |offer|
          {
            price: offer.price,
            price_currency: offer.price_currency,
            payment_frequency: offer.payment_frequency,
            category: offer.category,
          }
        end
      rescue ActiveRecord::RecordNotFound
        []
      end

      def paid?(course)
        if Course::Course.find(course['id']).offers.any?
          offers_for(course).pluck(:price).sum.positive?
        else
          false
        end
      rescue ActiveRecord::RecordNotFound
        false
      end

      def course_api
        @course_api ||= Xikolo.api(:course).value!
      end

      def api_config
        Xikolo.config.moochub_api
      end
    end
    # rubocop:enable all
  end
end
