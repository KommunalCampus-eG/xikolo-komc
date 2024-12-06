# frozen_string_literal: true

FactoryBot.define do
  factory :fork do
    transient do
      # Ensure that all associations are associated to the same course
      course do
        @overrides[:content_test]&.course || # Use the course from the content test if passed in
          @overrides[:section]&.course || # Use the course from the section if passed in
          create(:course, :with_content_tree) # Create one if both associations have to be created
      end
    end

    content_test { association(:content_test, course:) }
    section { association(:section, course:) }
  end
end
