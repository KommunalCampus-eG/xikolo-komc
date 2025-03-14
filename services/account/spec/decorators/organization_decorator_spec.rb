# frozen_string_literal: true

require 'spec_helper'

describe OrganizationDecorator, type: :decorator do
  let(:organization) { create(:organization) }
  let(:decorator) { described_class.new organization }

  describe '#as_json' do
    subject(:json) { decorator.as_json }

    it 'includes the correct properties' do
      expect(json.keys).to match_array %w[
        id
        name
      ]
    end

    it { is_expected.to include 'id' => organization.id }
    it { is_expected.to include 'name' => organization.name }
  end
end
