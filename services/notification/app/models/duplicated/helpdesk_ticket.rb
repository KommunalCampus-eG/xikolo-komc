# frozen_string_literal: true

# We are temporarily duplicating the Helpdesk::Ticket model from xi-web
module Duplicated
  class HelpdeskTicket < ApplicationRecord
    self.table_name = 'tickets'

    scope :created_last_day, -> { where(created_at: 1.day.ago..) }
  end
end
