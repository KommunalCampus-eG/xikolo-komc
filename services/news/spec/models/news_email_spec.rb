# frozen_string_literal: true

require 'spec_helper'

describe Email, type: :model do
  subject { email }

  let(:attributes) { {} }
  let(:email) { create(:email, attributes) }

  describe '#send' do
    context 'with publish date set in the future' do
      let(:attributes) { {announcement: create(:news, publish_at: 1.day.from_now)} }

      it 'does not publish anything' do
        expect(Msgr).not_to receive(:publish)
        email.send!
      end
    end

    context 'with sent status' do
      let(:attributes) { {announcement: create(:news, publish_at: 1.day.from_now), status: :sent} }

      it 'does not publish anything' do
        expect(Msgr).not_to receive(:publish)
        email.send!
      end
    end

    context 'with canceled status' do
      let(:attributes) { {announcement: create(:news, publish_at: 1.day.from_now), status: :canceled} }

      it 'does not publish anything' do
        expect(Msgr).not_to receive(:publish)
        email.send!
      end
    end

    context 'for a global announcement' do
      let(:attributes) { {announcement: create(:news, :global)} }

      it 'publishes the correct event payload' do
        expect(Msgr).to receive(:publish) do |*args|
          expect(args[0]).to include course_id: nil
          expect(args[1]).to eq(to: 'xikolo.news.announcement.create')
        end
        email.send!
      end
    end

    context 'for a group-restricted global announcement' do
      let(:attributes) { {announcement: create(:news, :global, audience: 'xikolo.affiliated')} }

      it 'includes the group name in the event payload' do
        expect(Msgr).to receive(:publish) do |*args|
          expect(args[0]).to include course_id: nil, group: 'xikolo.affiliated'
          expect(args[1]).to eq(to: 'xikolo.news.announcement.create')
        end
        email.send!
      end
    end

    context 'with explicit receiver for test email' do
      let(:receiver_id) { SecureRandom.uuid }
      let(:attributes) { {announcement: create(:news, :global, audience: 'xikolo.affiliated'), test_recipient: receiver_id} }

      it 'forwards the receiver ID' do
        expect(Msgr).to receive(:publish) do |*args|
          expect(args[0]).to include(receiver_id:)
          expect(args[1]).to eq(to: 'xikolo.news.announcement.create')
        end
        email.send!
      end
    end
  end
end
