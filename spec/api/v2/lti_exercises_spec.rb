# frozen_string_literal: true

require 'spec_helper'

describe Xikolo::V2::CourseItems::LtiExercises do
  include Rack::Test::Methods

  def app
    Xikolo::API
  end

  let(:stub_session_id) { "token=#{SecureRandom.hex(16)}" }
  let(:permissions) { ['course.content.access.available'] }

  let(:item) { create(:item, :lti_exercise) }

  let(:env_hash) do
    {
      'CONTENT_TYPE' => 'application/vnd.api+json',
      'HTTP_AUTHORIZATION' => "Legacy-Token #{stub_session_id}",
    }
  end

  before do
    Stub.service(
      :account,
      session_url: '/sessions/{id}'
    )
    api_stub_user
    api_stub_user permissions:, context_id: item.section.course.context_id
  end

  describe 'GET lti-exercises/:id' do
    subject(:response) { get "/v2/lti-exercises/#{item.content_id}", nil, env_hash }

    it 'responds with 200 Ok' do
      expect(response.status).to eq 200
    end

    context 'without an enrollment' do
      let(:permissions) { [] }

      it 'responds with 403 Forbidden' do
        expect(response.status).to eq 403
      end
    end

    context 'as an administrator' do
      let(:permissions) { ['course.content.access'] }

      it 'responds with 200 Ok' do
        expect(response.status).to eq 200
      end
    end

    context 'without a corresponding item' do
      let(:item) { create(:item) }

      it 'responds with 404 Not Found' do
        expect(response.status).to eq 404
      end
    end
  end
end
