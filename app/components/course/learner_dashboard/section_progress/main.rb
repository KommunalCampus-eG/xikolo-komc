# frozen_string_literal: true

module Course
  module LearnerDashboard
    module SectionProgress
      class Main < ApplicationComponent
        include ProgressHelper

        def initialize(section_progress, course)
          @section_progress = section_progress
          @course = course
        end

        def main_statistic
          @section_progress['main_exercises']
        end

        def bonus_statistic
          @section_progress['bonus_exercises']
        end

        def selftest_statistic
          @section_progress['selftest_exercises']
        end

        def items
          # `@section_progress['items']` may be `nil` if the section is not available.
          # Make sure to always return an enumerable object and avoid a tri-state.

          @section_progress['items'].presence || []
        end

        def graded_percentage
          return if main_statistic.blank? || main_statistic['max_points'].zero?

          achieved_points = [
            main_statistic['submitted_points'].presence,
            bonus_statistic&.dig('submitted_points').presence,
          ].compact.sum

          calc_progress(achieved_points, main_statistic['max_points'])
        end

        def selftest_percentage
          return if selftest_statistic.blank? || selftest_statistic['max_points'].zero?

          calc_progress(selftest_statistic['submitted_points'], selftest_statistic['max_points'])
        end

        def visits_percentage
          return if @section_progress['visits'].blank? || items_available.zero?

          @section_progress['visits']['percentage']
        end

        def items_visited
          @section_progress.dig('visits', 'user').presence || 0
        end

        def items_available
          @section_progress.dig('visits', 'total').presence || 0
        end
      end
    end
  end
end
