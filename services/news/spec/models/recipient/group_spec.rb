# frozen_string_literal: true

require 'spec_helper'

describe Recipient::Group, type: :model do
  subject(:recipient) { described_class.new 'the.id', message }

  let(:message) { create(:message) }

  before do
    Stub.service(:account, build(:'account:root'))
    Stub.request(:account, :get, '/groups/the.id')
      .to_return Stub.json({members_url: '/groups/the.id/members'})

    Stub.request(:account, :get, '/groups/the.id/members')
      .to_return Stub.json(
        [{id: 1}, {id: 2}],
        headers: {
          'Link' => '</groups/the.id/members?page=2>; rel="next"',
        }
      )
    Stub.request(:account, :get, '/groups/the.id/members?page=2')
      .to_return Stub.json([{id: 3}, {id: 4}])
  end

  describe '.each' do
    it 'returns an enumerator' do
      expect(recipient.each).to be_an Enumerator
    end

    it 'yields for all members' do
      expect {|b| recipient.each(&b) }.to yield_control.exactly(4).times
    end

    it 'enumerates over all pages' do
      recipient.each.tap do |enumerator|
        expect(enumerator.next).to eq 'id' => 1
        expect(enumerator.next).to eq 'id' => 2
        expect(enumerator.next).to eq 'id' => 3
        expect(enumerator.next).to eq 'id' => 4
      end
    end
  end
end
