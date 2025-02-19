# frozen_string_literal: true

class AddStatusToNewsEmails < ActiveRecord::Migration[6.1]
  def change
    add_column :news_emails, :status, :integer, default: 0, null: false

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE news_emails
          SET status = 1
        SQL
      end
    end
  end
end
