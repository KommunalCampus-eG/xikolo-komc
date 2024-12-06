# frozen_string_literal: true

FactoryBot.define do
  factory :course_set_relation do
    association :source_set, factory: [:course_set]
    association :target_set, factory: [:course_set]
  end
end
