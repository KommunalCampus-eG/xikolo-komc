# frozen_string_literal: true

require 'spec_helper'

describe 'Portal API: List enrollments', type: :request do
  subject(:request) do
    get '/portalapi-beta/enrollments', headers:, params:
  end

  let(:headers) { {} }
  let(:params) { {} }
  let(:json) { JSON.parse response.body }
  let(:user_id) { '00000001-3100-4444-9999-000000000099' }
  let(:courses) { create_list(:course, 3) }
  let(:enrollments) do
    courses.map do |c|
      build(:'course:enrollment',
        user_id:,
        course_id: c.id,
        created_at: 1.day.ago,
        completed: false,
        deleted: false,
        certificates: {
          'certificate' => false,
          'confirmation_of_participation' => false,
          'record_of_achievement' => false,
          'transcript_of_records' => false,
        })
    end
  end

  before do
    stub_user_request id: user_id

    Stub.service(:course, build(:'course:root'))
  end

  context 'without Authorization header' do
    it 'responds with 401 Unauthorized' do
      request
      expect(response).to have_http_status :unauthorized
      expect(response.headers['WWW-Authenticate']).to eq 'Bearer realm="test-realm"'
      expect(response.headers['Content-Type']).to eq 'application/problem+json; charset=utf-8'
      expect(json).to eq(
        'type' => 'https://openhpi.stoplight.io/docs/portal-api/068d6638d8e0b-errors#unauthenticated',
        'title' => 'You must provide an Authorization header to access this resource.',
        'status' => 401
      )
    end

    it 'answers in context of the configured realm' do
      request
      expect(response.header['WWW-Authenticate']).to include('realm="test-realm"')
    end
  end

  context 'with an invalid authorization token' do
    let(:headers) do
      super().merge('Authorization' => 'Bearer canihackyou')
    end

    it 'responds with 401 Unauthorized' do
      request
      expect(response).to have_http_status :unauthorized
      expect(response.headers['WWW-Authenticate']).to eq 'Bearer realm="test-realm", error="invalid_token"'
      expect(response.headers['Content-Type']).to eq 'application/problem+json; charset=utf-8'
      expect(json).to eq(
        'type' => 'https://openhpi.stoplight.io/docs/portal-api/068d6638d8e0b-errors#invalid_token',
        'title' => 'The bearer token you provided was invalid, has expired or has been revoked.',
        'status' => 401
      )
    end
  end

  context 'with an Authorization header (with a hardcoded token)' do
    let(:headers) do
      super().merge('Authorization' => 'Bearer 78f6d8ca88c65a67c9dffa3c232313d64b4e338e29d7c83ef39c2e963894b966')
    end

    context 'without an Accept header' do
      let(:headers) do
        super().merge('Accept' => nil)
      end

      it 'responds with HTTP 406 Not Acceptable' do
        request
        expect(response).to have_http_status :not_acceptable
        expect(response.headers['Content-Type']).to eq 'application/problem+json; charset=utf-8'
        expect(json).to eq(
          'type' => 'https://openhpi.stoplight.io/docs/portal-api/068d6638d8e0b-errors#accept_header_missing',
          'title' => 'You must provide the desired content type in the Accept request header.',
          'status' => 406
        )
      end
    end

    context 'with an unsupported content type in the Accept header' do
      let(:headers) do
        super().merge('Accept' => 'application/vnd.openhpi.enrollments+json;v=0.9')
      end

      it 'responds with HTTP 406 Not Acceptable' do
        request
        expect(response).to have_http_status :not_acceptable
        expect(response.headers['Content-Type']).to eq 'application/problem+json; charset=utf-8'
        expect(json).to eq(
          'type' => 'https://openhpi.stoplight.io/docs/portal-api/068d6638d8e0b-errors#unsupported_content_type',
          'title' => 'The media type provided in the "Accept" request header is not supported by this endpoint.',
          'status' => 406
        )
      end
    end

    context 'with a supported content type in the Accept header' do
      let(:headers) do
        super().merge('Accept' => 'application/vnd.openhpi.enrollments+json;v=1.0')
      end

      context 'without a user ID' do
        let(:params) { super().merge(course_id: generate(:course_id)) }

        it 'responds with HTTP 422 Unprocessable Entity' do
          request
          expect(response).to have_http_status :unprocessable_entity
          expect(response.headers['Content-Type']).to eq 'application/problem+json; charset=utf-8'
          expect(json).to eq(
            'type' => 'https://openhpi.stoplight.io/docs/portal-api/068d6638d8e0b-errors#parameter_missing',
            'title' => 'The user_id cannot be blank.',
            'status' => 422
          )
        end
      end

      context 'with an unknown user' do
        let(:params) do
          super().merge(
            user_id: '00000001-3100-4444-9999-000000000100',
            course_id: generate(:course_id)
          )
        end

        before do
          Stub.request(
            :course, :get, '/enrollments',
            query: {
              user_id: '00000001-3100-4444-9999-000000000100',
              course_id: params[:course_id],
              learning_evaluation: true,
            }
          ).to_return Stub.json([])
        end

        it 'responds with an empty list' do
          request
          expect(response).to have_http_status :ok
          expect(response.headers['Content-Type']).to eq 'application/vnd.openhpi.enrollments+json;v=1.0'
          expect(json).to be_empty
        end
      end

      context 'with an enrollment for the user in the specified course' do
        let(:params) do
          super().merge(
            user_id: enrollments.first['user_id'],
            course_id: enrollments.first['course_id']
          )
        end

        before do
          Stub.request(
            :course, :get, '/enrollments',
            query: {
              user_id: enrollments.first['user_id'],
              course_id: enrollments.first['course_id'],
              learning_evaluation: true,
            }
          ).to_return Stub.json([enrollments.first])
        end

        it 'responds with the user\'s enrollment for the course' do
          request
          expect(response).to have_http_status :ok
          expect(response.headers['Content-Type']).to eq 'application/vnd.openhpi.enrollments+json;v=1.0'
          expect(json).to contain_exactly({
            'id' => enrollments.first['id'],
            'course_id' => enrollments.first['course_id'],
            'created_at' => enrollments.first['created_at'],
            'completed' => false,
            'deleted' => false,
            'achievements' => {
              'certificate' => false,
              'confirmation_of_participation' => false,
              'record_of_achievement' => false,
              'transcript_of_records' => false,
            },
          })
        end
      end

      context 'when requesting all enrollments of the user' do
        let(:params) { super().merge(user_id:) }

        before do
          Stub.request(
            :course, :get, '/enrollments',
            query: {
              user_id:,
              learning_evaluation: true,
            }
          ).to_return Stub.json(enrollments)
        end

        it 'responds with all user enrollments' do
          request
          expect(response).to have_http_status :ok
          expect(response.headers['Content-Type']).to eq 'application/vnd.openhpi.enrollments+json;v=1.0'
          expect(json.size).to eq 3
          expect(json.pluck('id', 'course_id')).to match_array enrollments.pluck('id', 'course_id')
          expect(json).to all match hash_including(
            'completed' => false,
            'deleted' => false,
            'achievements' => {
              'certificate' => false,
              'confirmation_of_participation' => false,
              'record_of_achievement' => false,
              'transcript_of_records' => false,
            }
          )
          expect(json.pluck('created_at').map(&:to_time)).to all be_within(1.minute).of(1.day.ago)
        end
      end
    end
  end
end
