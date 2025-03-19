# frozen_string_literal: true

class AddOrganizationIDToUsers < ActiveRecord::Migration[6.1]
  def change
    add_reference :users, :organization, type: :uuid, foreign_key: true, null: true
  end
end
