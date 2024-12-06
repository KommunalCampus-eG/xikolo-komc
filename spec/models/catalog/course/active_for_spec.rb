# frozen_string_literal: true

require 'spec_helper'

describe Catalog::Course, '.active_for', type: :model do
  subject(:scope) { described_class.active_for(user, enrollments) }

  let(:user) { Xikolo::Common::Auth::CurrentUser.from_session(user_session) }
  let(:enrollments) { [] }
  let(:user_id) { generate(:user_id) }
  let(:user_session) do
    {
      'masqueraded' => false,
      'user_id' => user_id,
      'user' => {
        'anonymous' => false,
        'language' => I18n.locale,
        'preferred_language' => I18n.locale,
      },
    }
  end

  before do
    course1 = create(:course,
      title: 'A non-published course that would run now',
      status: 'preparation',
      start_date: 1.week.ago,
      end_date: 1.month.from_now)
    enrollments << create(:enrollment, course: course1, user_id:)

    course2 = create(:course,
      title: 'A non-published course without dates',
      status: 'preparation',
      start_date: nil,
      end_date: nil)
    enrollments << create(:enrollment, course: course2, user_id:)

    course3 = create(:course,
      title: 'An upcoming course in preparation',
      status: 'preparation',
      start_date: 5.months.from_now,
      end_date: 6.months.from_now)
    enrollments << create(:enrollment, course: course3, user_id:)

    course4 = create(:course,
      title: 'A published future course',
      status: 'active',
      start_date: Date.tomorrow,
      end_date: nil)
    enrollments << create(:enrollment, course: course4, user_id:)

    course5 = create(:course,
      title: 'A never ending course with start date',
      status: 'active',
      start_date: Date.yesterday,
      end_date: nil)
    enrollments << create(:enrollment, course: course5, user_id:)

    course6 = create(:course,
      title: 'A never ending course without start date',
      status: 'active',
      start_date: nil,
      end_date: nil)
    enrollments << create(:enrollment, course: course6, user_id:)

    course7 = create(:course,
      title: 'An archived course',
      status: 'archive',
      start_date: 1.month.ago,
      end_date: 5.days.ago)
    enrollments << create(:enrollment, course: course7, user_id:)

    course8 = create(:course,
      title: 'An active course with past end date',
      status: 'active',
      start_date: 1.month.ago,
      end_date: 1.day.ago)
    enrollments << create(:enrollment, course: course8, user_id:)

    course9 = create(:course,
      title: 'An active and current course',
      status: 'active',
      start_date: 5.days.ago,
      end_date: 1.month.from_now)
    enrollments << create(:enrollment, course: course9, user_id:)

    course10 = create(:course,
      title: 'An active and current course (completed)',
      status: 'active',
      start_date: 5.days.ago,
      end_date: 1.month.from_now)
    enrollments << create(:enrollment, course: course10, user_id:, completed: true)

    create(:course,
      title: 'An active and current course (not enrolled)',
      status: 'active',
      start_date: 5.days.ago,
      end_date: 1.month.from_now)

    # The following stubs are needed to remove already completed courses.
    Stub.service(:course, build(:'course:root'))
    Stub.request(
      :course, :get, '/enrollments',
      query: hash_including(user_id:, learning_evaluation: 'true')
    ).to_return Stub.json([
      build(:'course:enrollment:evaluated', user_id:, course_id: course10.id),
    ])
  end

  it 'returns all non-completed courses the user is enrolled in' do
    expect(scope).to contain_exactly(
      have_attributes(title: 'A non-published course without dates'),
      have_attributes(title: 'A never ending course with start date'),
      have_attributes(title: 'A never ending course without start date'),
      have_attributes(title: 'An archived course'),
      have_attributes(title: 'An active course with past end date'),
      have_attributes(title: 'An active and current course')
    )
  end

  describe 'sorting' do
    let(:enrollments) { [] }

    before do
      one_month_ago = 1.month.ago
      two_months_ago = 2.months.ago

      course1 = create(:course,
        title: 'Ended one month ago',
        status: 'active',
        start_date: two_months_ago,
        end_date: one_month_ago)
      enrollments << create(:enrollment, course: course1, user_id:)

      course2 = create(:course,
        title: 'Ended one month ago, but with another title',
        status: 'active',
        start_date: two_months_ago,
        end_date: one_month_ago)
      enrollments << create(:enrollment, course: course2, user_id:)

      course3 = create(:course,
        title: 'A never ending course with display start date',
        status: 'active',
        start_date: 3.hours.ago,
        display_start_date: 3.days.ago,
        end_date: nil)
      enrollments << create(:enrollment, course: course3, user_id:)
    end

    it 'returns recently started courses first and prefers the display start date over the start date' do
      expect(scope).to match [
        have_attributes(title: 'A never ending course with start date'), # started one day ago
        have_attributes(title: 'A never ending course with display start date'), # displayed as started three days ago
        have_attributes(title: 'An active and current course'), # started five days ago, ends one month from now
        have_attributes(title: 'An active course with past end date'), # started one month ago, ended one day ago
        have_attributes(title: 'An archived course'), # started one month ago, ended five days ago
        have_attributes(title: 'Ended one month ago'), # started two months ago, ended one month ago
        have_attributes(title: 'Ended one month ago, but with another title'), # started two months ago, ended one month ago
        have_attributes(title: 'A never ending course without start date'),
        have_attributes(title: 'A non-published course without dates'), # not published, but enrolled
      ]
    end
  end
end
