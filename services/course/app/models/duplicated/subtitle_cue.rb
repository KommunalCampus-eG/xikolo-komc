# frozen_string_literal: true

module Duplicated
  class SubtitleCue < ApplicationRecord
    belongs_to :subtitle, class_name: '::Duplicated::Subtitle'

    # Use new interval type (default in Rails 7):
    attribute :start, :interval
    attribute :stop, :interval

    validates :identifier, presence: true, uniqueness: {scope: :subtitle_id}
    validates :start, :stop, presence: true
    validate :start_before_stop

    default_scope { order(identifier: :asc) }

    serialize :style, coder: YAML, type: Hash

    def clone(attrs = {})
      self.class.create attributes.except('id').merge(attrs)
    end

    private

    def start_before_stop
      return if start.blank? || stop.blank?

      if stop <= start
        errors.add(:stop, 'invalid')
      end
    end
  end
end
