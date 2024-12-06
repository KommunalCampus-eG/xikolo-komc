# frozen_string_literal: true

require 'spec_helper'

describe QuizSubmissionFreeTextAnswersController, type: :controller do
  let(:json) { JSON.parse response.body }
  let(:default_params) { {format: 'json'} }

  describe '#index' do
    it 'answers' do
      get :index
      expect(response).to have_http_status :ok
    end
  end
end
