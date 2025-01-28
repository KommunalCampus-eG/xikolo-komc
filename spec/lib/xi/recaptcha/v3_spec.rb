# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Xi::Recaptcha::V3 do
  subject(:recaptcha) { described_class.new(request:, params:, action:) }

  let(:request) { instance_double(ActionDispatch::Request) }
  let(:params) { {'recaptcha_token_v3' => 'valid_v3_token'} }
  let(:action) { 'helpdesk' }
  let(:recaptcha_score) { 0.5 }

  before do
    xi_config <<~YML
      recaptcha:
        enabled: true
        score: #{recaptcha_score}
        site_key_v2: 6Ld08WIqAAAAAMzWokw1WbhB2oY0LJRABkYC0Wrz
        site_key_v3: 6Lfz8GIqAAAAADuPSE0XXDa9XawEf0upsswLgsBA
    YML
  end

  describe '.site_key' do
    it 'returns the correct site key for reCAPTCHA v3' do
      expect(described_class.site_key).to eq('6Lfz8GIqAAAAADuPSE0XXDa9XawEf0upsswLgsBA')
    end
  end

  describe '#verified?' do
    context 'with recaptcha token' do
      it 'verifies the recaptcha and responds accordingly' do
        # rubocop:disable RSpec/SubjectStub
        # Do not test internal gem logic.
        allow(recaptcha).to receive(:verify_recaptcha).with(hash_including(
          action: 'helpdesk',
          minimum_score: recaptcha_score,
          secret_key: '6Lfz8GIqAAAAAI7luM866NJN5rdPx70hJDO2tsO3'
        )).and_return(true)
        # rubocop:enable RSpec/SubjectStub

        expect(recaptcha.verified?).to be true
      end
    end

    context 'without recaptcha token' do
      let(:params) { {} }

      it 'returns false' do
        expect(recaptcha.verified?).to be false
      end
    end
  end
end
