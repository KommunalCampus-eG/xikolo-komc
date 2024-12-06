# frozen_string_literal: true

require 'spec_helper'

describe AttemptsHandler, type: :handler do
  subject(:handler) { described_class.new(course_id, user_id) }

  let!(:quiz) { create(:quiz) }
  let(:user_id) { SecureRandom.uuid }
  let(:course_id) { SecureRandom.uuid }
  let(:section_id) { SecureRandom.uuid }

  before do
    Stub.service(
      :course,
      sections_url: '/sections',
      section_url: '/sections/{id}',
      items_url: '/items'
    )

    Stub.request(
      :course, :get, '/sections',
      query: {course_id:}
    ).to_return Stub.json([
      {id: section_id},
    ])

    Stub.request(
      :course, :get, '/items',
      query: {section_id:, content_type: 'quiz', exercise_type: 'main'}
    ).to_return Stub.json([
      {content_id: quiz.id},
    ])
  end

  describe '#unlock_assignments' do
    subject(:unlock) { handler.unlock_assignments }

    context 'with previous attempt' do
      before do
        create(:quiz_submission, :submitted, quiz_id: quiz.id, user_id:)
      end

      it 'creates an additional attempt' do
        expect { unlock }.to change {
          UserQuizAttempts.new(
            user_id:, quiz_id: quiz.id
          ).additional_attempts
        }.from(0).to(1)
      end
    end

    context 'without a previous attempt' do
      it 'does not create an additional attempt' do
        expect { unlock }.not_to change {
          UserQuizAttempts.new(
            user_id:, quiz_id: quiz.id
          ).additional_attempts
        }
      end
    end
  end
end
