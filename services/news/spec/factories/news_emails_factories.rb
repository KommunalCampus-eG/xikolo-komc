# frozen_string_literal: true

FactoryBot.define do
  factory :email do
    association :announcement
    status { :pending }
  end
end
