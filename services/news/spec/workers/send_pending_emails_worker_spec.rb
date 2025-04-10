# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SendPendingEmailsWorker, type: :worker do
  subject(:worker) { described_class }

  around do |example|
    Sidekiq::Testing.inline!(&example)
  end

  describe '#perform' do
    let(:sent_emails) { [] }

    before do
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Email).to receive(:send!) do |email|
        sent_emails << email.id
      end
      # rubocop:enable RSpec/AnyInstance
    end

    it 'sends pending emails with publish date in the past or present' do
      past_email = create(:email, announcement: create(:news, publish_at: 1.minute.ago))
      present_email = create(:email, announcement: create(:news, publish_at: Time.now.utc))

      worker.perform_async

      expect(sent_emails).to contain_exactly(past_email.id, present_email.id)
    end

    it 'sends pending emails without publish date' do
      email = create(:email, announcement: create(:news, publish_at: nil))

      worker.perform_async

      expect(sent_emails.count).to eq(1)
      expect(sent_emails).to include(email.id)
    end

    it 'does not send non-pending emails' do
      create(:email, announcement: create(:news, publish_at: 1.hour.ago), status: :sent)
      create(:email, announcement: create(:news, publish_at: 1.hour.ago), status: :canceled)

      worker.perform_async

      expect(sent_emails).to be_empty
    end

    it 'does not send emails with publish date in the future' do
      create(:email, announcement: create(:news, publish_at: 1.minute.from_now))
      create(:email, announcement: create(:news, publish_at: 1.month.from_now))

      worker.perform_async

      expect(sent_emails).to be_empty
    end
  end
end
