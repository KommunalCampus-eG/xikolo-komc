# frozen_string_literal: true

# The `ScheduleNewsEmailsWorker` processes all pending emails and sends those scheduled for the past, present,
# or without an associated publish date.
class SendPendingEmailsWorker
  include Sidekiq::Job

  def perform
    Email
      .pending
      .joins(:announcement)
      .where(news: {publish_at: [nil, ..Time.now.utc]})
      .in_batches(of: 100) do |batch|
      batch.each(&:send!)
    end
  end
end
