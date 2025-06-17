# frozen_string_literal: true

module Account
  class Organization < ::ApplicationRecord
    has_many :users,
      class_name: 'Account::User',
      dependent: :nullify
  end
end
