# frozen_string_literal: true

module Duplicated
  class LtiProvider < ApplicationRecord
    has_many :lti_exercises, class_name: '::Duplicated::LtiExercise'

    attribute :privacy, :string, default: 'anonymized'

    validates :consumer_key, presence: true
    validates :name, presence: true
    validates :domain, format: {with: URI::DEFAULT_PARSER.make_regexp}, presence: true
    validates :shared_secret, presence: true
    validates :presentation_mode, presence: true, inclusion: %w[frame pop-up window]
    validates :privacy, inclusion: {in: %w[anonymized pseudonymized unprotected]}

    def global?
      course_id.nil?
    end

    def anonymized?
      privacy == 'anonymized'
    end

    def pseudonymized?
      privacy == 'pseudonymized'
    end
  end
end
