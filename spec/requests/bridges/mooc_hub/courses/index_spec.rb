# frozen_string_literal: true

require 'spec_helper'

describe 'MOOCHub API: Index', type: :request do
  subject(:request) do
    get '/bridges/moochub/courses', params:, headers: request_headers
  end

  let(:params) { {} }
  let(:request_headers) { {} }
  let(:json) { JSON.parse response.body }
  let(:courses) { create_list(:course, 4, :with_visual) }
  let(:courses_resources) do
    courses.map do |c|
      build(
        :'course:course',
        id: c.id,
        course_code: c.course_code,
        abstract: c.abstract,
        classifiers: c.classifiers,
        title: c.title,
        start_date: c.start_date,
        end_date: c.end_date
      )
    end
  end
  let(:stub_courses) do
    Stub.request(
      :course, :get, '/courses',
      query: {
        public: true,
        exclude_external: true,
        hidden: false,
        alphabetic: true,
        page: 1,
        active_after: '2018-04-07',
      }
    ).to_return Stub.json(courses_resources)
  end

  around do |example|
    date = Date.new(2021, 4, 7)
    Timecop.freeze(date) { example.run }
  end

  shared_examples_for 'a successful request' do
    before { request }

    it { expect(response).to have_http_status :ok }
  end

  before do
    xi_config <<~YML
      moochub_api:
        enabled: true
        course_license:
          default:
            id: 'CC-BY-NC-SA-4.0'
            url: 'https://creativecommons.org/licenses/by-nc-sa/4.0'
        course_metadata:
          organization:
            name: "Company Name"
            identifier: 'https://companyname.de/'
            type: "Organization"
    YML

    Stub.service(:course, build(:'course:root'))
    stub_courses
    courses.map do |course|
      Stub.request(
        :course, :get, "/teachers?course=#{course.id}"
      ).to_return Stub.json([])
    end
  end

  it 'responds with current version (no Accept header set)' do
    request
    expect(response.headers['Content-Type']).to eq 'application/vnd.api+json; moochub-version=3.0; charset=utf-8'
  end

  context 'with Accept header for current major version' do
    let(:request_headers) { {'Accept' => 'application/vnd.api+json; moochub-version=3'} }

    it_behaves_like 'a successful request'

    it 'responds with a compatible version' do
      request
      expect(response.headers['Content-Type']).to eq 'application/vnd.api+json; moochub-version=3.0; charset=utf-8'
    end
  end

  context 'with Accept header for an unsupported version' do
    let(:request_headers) { {'Accept' => 'application/vnd.api+json; moochub-version=0.5'} }

    it 'responds with Not Acceptable' do
      request

      expect(response).to have_http_status :not_acceptable
      expect(response.headers['Content-Type']).to eq 'application/problem+json; charset=utf-8'
      expect(json['title']).to eq 'Unsupported version requested'
      expect(json['status']).to eq 406
    end
  end

  describe 'courses' do
    let(:request_headers) { {'Accept' => 'application/vnd.api+json; moochub-version=3.0'} }
    let(:stub_courses) do
      Stub.request(
        :course, :get, '/courses',
        query: {
          public: true,
          exclude_external: true,
          hidden: false,
          alphabetic: true,
          page: 1,
          active_after: '2018-04-07',
        }
      ).to_return Stub.json(courses_resources)
    end

    it_behaves_like 'a successful request'

    it 'responds with a compatible version' do
      request

      expect(response.headers['Content-Type']).to eq 'application/vnd.api+json; moochub-version=3.0; charset=utf-8'
    end

    it 'responds with courses' do
      request
      expect(json['data'].length).to eq 4
      expect(json['data']).to all match({
        'type' => 'Course',
        'id' => kind_of(String),
        'attributes' => kind_of(Hash),
      })
      expect(json['data'].pluck('attributes').map(&:keys)).to all contain_exactly(
        'name',
        'courseCode',
        'courseMode',
        'abstract',
        'description',
        'inLanguage',
        'startDate',
        'endDate',
        'image',
        'instructors',
        'duration',
        'partnerInstitute',
        'moocProvider',
        'license',
        'access',
        'url',
        'offers',
        'keywords',
        'teaches',
        'educationalAlignment',
        'publisher',
        'creator',
        'learningResourceType'
      )
    end

    describe '(dates)' do
      it 'date values are Arrays' do
        request

        expect(json['data'].first.dig('attributes', 'startDate')).to be_an_instance_of(Array)
        expect(json['data'].first.dig('attributes', 'endDate')).to be_an_instance_of(Array)
      end
    end
  end

  describe 'abstract' do
    let(:courses) { create_list(:course, 1, abstract: 'This is the *course* abstract.') }
    let(:courses_resources) do
      courses.map do |c|
        build(:'course:course', id: c.id, course_code: c.course_code, abstract: c.abstract)
      end
    end

    it_behaves_like 'a successful request'

    it 'returns the abstract as HTML' do
      request
      expect(json.dig('data', 0, 'attributes', 'abstract')).to eq \
        <<~HTML
          <p>This is the <em>course</em> abstract.</p>
        HTML
    end

    context 'with empty abstract' do
      let(:courses) { create_list(:course, 1, abstract: '') }

      it_behaves_like 'a successful request'

      it 'returns nil (instead of empty string)' do
        request
        expect(json.dig('data', 0, 'attributes', 'abstract')).to be_nil
      end
    end
  end

  describe 'instructors' do
    context 'without course teachers' do
      it_behaves_like 'a successful request'

      it 'responds with an empty array' do
        request
        expect(json.dig('data', 0, 'attributes', 'instructors')).to eq []
      end
    end

    context 'with course teachers' do
      let(:courses) { create_list(:course, 1) }
      let(:courses_resources) do
        courses.map {|c| build(:'course:course', id: c.id, course_code: c.course_code, teacher_text: 'Teacher 1, Teacher 2') }
      end

      it_behaves_like 'a successful request'

      it 'responds with the correct instructor information' do
        request
        expect(json.dig('data', 0, 'attributes', 'instructors').length).to eq 2
        expect(json.dig('data', 0, 'attributes', 'instructors').pluck('name')).to contain_exactly('Teacher 1', 'Teacher 2')
      end
    end
  end

  describe 'duration' do
    let(:courses) { create_list(:course, 1, start_date: end_date - 2.weeks, end_date:) }
    let(:courses_resources) do
      courses.map {|c| build(:'course:course', id: c.id, course_code: c.course_code, start_date: c.start_date, end_date: c.end_date) }
    end
    let(:end_date) { Time.new(2020, 10, 10, 12, 0, 0).in_time_zone }

    it_behaves_like 'a successful request'

    it 'responds with the correct duration' do
      request
      expect(json.dig('data', 0, 'attributes', 'duration')).to eq 'P2W'
    end

    context 'for period of days' do
      let(:courses) { create_list(:course, 1, start_date: end_date - 2.days, end_date:) }

      it_behaves_like 'a successful request'

      it 'responds with the correct duration' do
        request
        expect(json.dig('data', 0, 'attributes', 'duration')).to eq 'P2D'
      end
    end

    context 'course with "detailed" start and end dates' do
      let(:courses) { create_list(:course, 1, start_date: end_date - 2.days + 15.minutes, end_date:) }
      let(:end_date) { Time.new(2020, 10, 10, 12, 30, 10).in_time_zone }

      it_behaves_like 'a successful request'

      it 'doesn\'t include minutes and seconds' do
        request
        expect(json.dig('data', 0, 'attributes', 'duration')).to eq 'P1DT23H45M'
      end
    end

    context 'course without proper start and end dates' do
      let(:courses) { create_list(:course, 1, start_date: 2.weeks.ago, end_date: nil) }

      it_behaves_like 'a successful request'

      it 'responds with the correct duration' do
        request
        expect(json.dig('data', 0, 'attributes', 'duration')).to be_nil
      end
    end
  end

  describe 'partnerInstitute' do
    it_behaves_like 'a successful request'

    it 'responds with no information' do
      request
      expect(json.dig('data', 0, 'attributes', 'partnerInstitute')).to be_empty
    end
  end

  describe 'moocProvider' do
    it_behaves_like 'a successful request'

    it 'responds with the correct MOOC provider information' do
      request
      expect(json['data'].length).to eq 4
      expect(json.dig('data', 0, 'attributes', 'moocProvider')).to include(
        'name' => 'Xikolo',
        'url' => 'http://www.example.com/',
        'logo' => %r{\Ahttp://www.example.com/assets/logo-[a-z0-9]+.png}
      )
    end
  end

  describe 'access' do
    let(:courses) { create_list(:course, 1) }

    it_behaves_like 'a successful request'

    it 'is free of charge by default' do
      request
      expect(json.dig('data', 0, 'attributes', 'access')).to eq %w[free]
    end

    context 'for courses with a paid offer' do
      before do
        courses.each {|c| create(:offer, course: c, price: 10) }
      end

      it_behaves_like 'a successful request'

      it 'the course is not accessible for free' do
        request
        expect(json.dig('data', 0, 'attributes', 'access')).to eq %w[paid]
      end
    end
  end

  describe '(course) url' do
    let(:courses) { create_list(:course, 1, course_code: 'specific-course') }

    before do
      xi_config <<~YML
        moochub_api:
          enabled: true
      YML
    end

    it_behaves_like 'a successful request'

    it 'returns the correct (not adjusted) course URL' do
      request
      expect(json['data'].length).to eq 1
      expect(json.dig('data', 0, 'attributes', 'url')).to eq 'https://xikolo.de/courses/specific-course'
    end

    context 'for a platform with different public course URL' do
      before do
        xi_config <<~YML
          moochub_api:
            enabled: true
          public_course_page:
            url_template: https://example.com/courses{/course_code}
        YML
      end

      it_behaves_like 'a successful request'

      it 'returns the correctly adjusted course URL' do
        request
        expect(json['data'].length).to eq 1
        expect(json.dig('data', 0, 'attributes', 'url')).to eq 'https://example.com/courses/specific-course'
      end
    end
  end

  describe 'publisher and creator' do
    let(:request_headers) { {'Accept' => 'application/vnd.api+json; moochub-version=3.0'} }
    let(:stub_courses) do
      Stub.request(
        :course, :get, '/courses',
        query: {
          public: true,
          exclude_external: true,
          hidden: false,
          alphabetic: true,
          page: 1,
          active_after: '2018-04-07',
        }
      ).to_return Stub.json(courses_resources)
    end

    before do
      xi_config <<~YML
        moochub_api:
          enabled: true
          course_license:
            default:
              id: 'CC-BY-NC-SA-4.0'
              url: 'https://creativecommons.org/licenses/by-nc-sa/4.0'
              name: 'Creative Commons Attribution Non Commercial Share Alike 4.0 International'
              author: 'My company'
          course_metadata:
            organization:
              name: 'Company name'
              identifier: 'https://companyname.de/'
              type: "Organization"
              description: "Interesting company name description."
              image:
                description: "test"
                type: "ImageObject"
                contentUrl: "test"
                license: [{ identifier: "proprietary", url: ~ }]
            creator:
              license:
                - identifier: 'proprietary'
                  url: ~
      YML
    end

    context 'without course teachers' do
      let(:courses) { create_list(:course, 1) }

      it_behaves_like 'a successful request'

      it 'responds with the correct publisher information' do
        request

        expect(json.dig('data', 0, 'attributes', 'publisher')).to match hash_including(
          'name' => 'Company name',
          'identifier' => 'https://companyname.de/',
          'type' => 'Organization',
          'image' => {
            'description' => 'test',
            'type' => 'ImageObject',
            'contentUrl' => 'test',
            'license' => [{'identifier' => 'proprietary', 'url' => nil}],
          }
        )
      end

      it 'responds with organization information as a fallback for creator' do
        request
        expect(json.dig('data', 0, 'attributes', 'creator')).to contain_exactly(
          hash_including(
            'name' => 'Company name',
            'identifier' => 'https://companyname.de/',
            'type' => 'Organization'
          )
        )
      end
    end

    context 'with course teachers' do
      before do
        courses.map do |course|
          Stub.request(
            :course, :get, "/teachers?course=#{course.id}"
          ).to_return Stub.json([teacher_1, teacher_2])
        end
      end

      let(:teacher_1) { build(:'course:teacher') }
      let(:teacher_2) do
        build(:'course:teacher',
          name: 'Prof. Dr. Jane Doe',
          picture_url: 'https://example.com/teacher_doe.png')
      end
      let(:courses) { create_list(:course, 1, lang: 'de') }
      let(:courses_resources) do
        courses.map do |c|
          build(:'course:course', id: c.id, course_code: c.course_code,
            teacher_ids: [teacher_1['id'], teacher_2['id']],
            lang: c.lang)
        end
      end

      it_behaves_like 'a successful request'

      it 'responds with the correct publisher information' do
        request

        expect(json.dig('data', 0, 'attributes', 'publisher')).to match hash_including(
          'name' => 'Company name',
          'description' => 'Interesting company name description.'
        )
      end

      it 'responds with the correct creator information' do
        request
        expect(json.dig('data', 0, 'attributes', 'creator')).to contain_exactly(
          hash_including(
            'name' => a_string_starting_with('Hans Otto'),
            'description' => 'Lehrer in Deutsch!'
          ),
          hash_including(
            'honorificPrefix' => 'Prof. Dr.',
            'name' => 'Jane Doe',
            'description' => 'Lehrer in Deutsch!',
            'image' => {
              'type' => 'ImageObject',
              'contentUrl' => 'https://example.com/teacher_doe.png',
              'license' => [{'identifier' => 'proprietary', 'url' => nil}],
            }
          )
        )
      end

      context 'with a missing teacher description for the course language' do
        let(:courses) { create_list(:course, 1, lang: 'nl') }

        it 'falls back to the default locale for the teacher description' do
          request
          expect(json.dig('data', 0, 'attributes', 'creator')).to contain_exactly(
            hash_including('description' => 'Teacher in English!'),
            hash_including('description' => 'Teacher in English!')
          )
        end
      end
    end

    context 'with missing organization config' do
      before do
        xi_config <<~YML
          moochub_api:
            enabled: true
            course_license:
              default:
                id: 'CC-BY-NC-SA-4.0'
                url: 'https://creativecommons.org/licenses/by-nc-sa/4.0'
                name: 'Creative Commons Attribution Non Commercial Share Alike 4.0 International'
                author: 'My company'
            course_metadata:
              organization: ~
        YML
      end

      it_behaves_like 'a successful request'

      it 'responds with the correct information' do
        request
        expect(json.dig('data', 0, 'attributes', 'publisher')).to be_nil
        expect(json.dig('data', 0, 'attributes', 'creator')).to be_empty
      end
    end

    context 'with invalid organization config' do
      before do
        xi_config <<~YML
          moochub_api:
            enabled: true
            course_license:
              default:
                id: 'CC-BY-NC-SA-4.0'
                url: 'https://creativecommons.org/licenses/by-nc-sa/4.0'
                name: 'Creative Commons Attribution Non Commercial Share Alike 4.0 International'
                author: 'My company'
            course_metadata:
              organization:
                name: ~
        YML
      end

      it_behaves_like 'a successful request'

      it 'responds with empty attributes' do
        request
        expect(json.dig('data', 0, 'attributes', 'publisher')).to be_blank
        expect(json.dig('data', 0, 'attributes', 'creator')).to be_blank
      end
    end
  end

  describe 'offers' do
    let(:request_headers) { {'Accept' => 'application/vnd.api+json; moochub-version=3.0'} }
    let(:stub_courses) do
      Stub.request(
        :course, :get, '/courses',
        query: {
          public: true,
          exclude_external: true,
          hidden: false,
          alphabetic: true,
          page: 1,
          active_after: '2018-04-07',
        }
      ).to_return Stub.json(courses_resources)
    end

    context 'without course offers' do
      let(:courses) { create_list(:course, 1, :archived) }

      it 'returns an empty value' do
        request

        expect(response).to have_http_status :ok
        expect(json.dig('data', 0, 'attributes', 'offers')).to be_empty
      end
    end

    context 'with course offer' do
      let(:courses) { create_list(:course, 1, :archived) }

      before { create(:offer, course: courses.first) }

      it 'includes all offer attributes' do
        request

        expect(json.dig('data', 0, 'attributes', 'offers').first).to match hash_including(
          'price' => 1000,
          'price_currency' => 'EUR',
          'payment_frequency' => 'one_time',
          'category' => 'course'
        )
      end
    end
  end

  describe 'keywords' do
    let(:request_headers) { {'Accept' => 'application/vnd.api+json; moochub-version=3.0'} }
    let(:stub_courses) do
      Stub.request(
        :course, :get, '/courses',
        query: {
          public: true,
          exclude_external: true,
          hidden: false,
          alphabetic: true,
          page: 1,
          active_after: '2018-04-07',
        }
      ).to_return Stub.json(courses_resources)
    end

    context 'when the "keywords" cluster does not exist' do
      let(:courses) { create_list(:course, 1, :archived) }

      it_behaves_like 'a successful request'

      it 'returns an empty value' do
        request

        expect(json.dig('data', 0, 'attributes', 'keywords')).to be_empty
      end
    end

    context 'when the "keywords" cluster exists' do
      let(:courses) { create_list(:course, 1, :archived, classifiers: [classifier, other_classifier]) }
      let!(:keywords_cluster) { create(:cluster, id: 'keywords') }
      let(:classifier) do
        create(:classifier, title: 'databases', translations: {'en' => 'Databases', 'de' => 'Datenbanken'}, cluster: keywords_cluster)
      end
      let(:other_classifier) do
        create(:classifier, title: 'testing', translations: {'en' => 'Testing', 'de' => 'Testen'}, cluster: keywords_cluster)
      end

      it_behaves_like 'a successful request'

      it 'responds with the "keywords" classifiers of the course' do
        request

        expect(json.dig('data', 0, 'attributes', 'keywords')).to contain_exactly('Databases', 'Testing')
      end
    end
  end

  describe 'teaches' do
    let(:request_headers) { {'Accept' => 'application/vnd.api+json; moochub-version=3.0'} }
    let(:stub_courses) do
      Stub.request(
        :course, :get, '/courses',
        query: {
          public: true,
          exclude_external: true,
          hidden: false,
          alphabetic: true,
          page: 1,
          active_after: '2018-04-07',
        }
      ).to_return Stub.json(courses_resources)
    end

    context 'without skills metadata' do
      let(:courses) { create_list(:course, 1, :archived) }

      it 'returns an empty value' do
        request

        expect(response).to have_http_status :ok
        expect(json.dig('data', 0, 'attributes', 'teaches')).to be_empty
      end
    end

    context 'with skills metadata' do
      let(:courses) { create_list(:course, 1, :archived, :with_skills_metadata) }

      it 'includes all skills attributes' do
        request

        expect(json.dig('data', 0, 'attributes', 'teaches').first).to include(
          'alternateName',
          'description',
          'url',
          'name',
          'shortCode',
          'targetUrl',
          'educationalLevel',
          'educationalFramework'
        )
      end
    end
  end

  describe 'educationalAlignment' do
    let(:request_headers) { {'Accept' => 'application/vnd.api+json; moochub-version=3.0'} }

    let(:stub_courses) do
      Stub.request(
        :course, :get, '/courses',
        query: {
          public: true,
          exclude_external: true,
          hidden: false,
          alphabetic: true,
          page: 1,
          active_after: '2018-04-07',
        }
      ).to_return Stub.json(courses_resources)
    end

    context 'without educational alignment metadata' do
      let(:courses) { create_list(:course, 1, :archived) }

      it 'returns an empty value' do
        request

        expect(response).to have_http_status :ok
        expect(json.dig('data', 0, 'attributes', 'educationalAlignment')).to be_empty
      end
    end

    context 'with educational alignment metadata' do
      let(:courses) { create_list(:course, 1, :archived, :with_educational_alignment_metadata) }

      it 'includes all skills attributes' do
        request

        expect(json.dig('data', 0, 'attributes', 'educationalAlignment').first).to include(
          'alignmentType',
          'alternateName',
          'description',
          'url',
          'name',
          'shortCode',
          'targetUrl',
          'educationalFramework'
        )
      end
    end
  end

  describe 'license' do
    let(:request_headers) { {'Accept' => 'application/vnd.api+json; moochub-version=3.0'} }
    let(:courses) { create_list(:course, 1) }

    context 'with license metadata' do
      before do
        create(:metadata, :license, course: courses.first)
      end

      it_behaves_like 'a successful request'

      it 'includes all license attributes' do
        request

        expect(json.dig('data', 0, 'attributes', 'license').length).to eq 1
        expect(json.dig('data', 0, 'attributes', 'license')).to contain_exactly({
          'identifier' => 'CC0-1.0',
          'url' => 'https: //creativecommons.org/publicdomain/zero/1.0',
          'contentUrl' => nil,
        })
        expect(json.dig('data', 0, 'attributes')).not_to include('courseLicenses')
      end
    end

    context 'without (course-specific) license metadata' do
      before do
        xi_config <<~YML
          moochub_api:
            enabled: true
            course_license:
              default:
                id: 'CC-BY-NC-SA-4.0'
                url: 'https://creativecommons.org/licenses/by-nc-sa/4.0'
                name: 'Creative Commons Attribution Non Commercial Share Alike 4.0 International'
                author: 'My company'
        YML
      end

      it_behaves_like 'a successful request'

      it 'returns the default platform license' do
        request
        expect(json.dig('data', 0, 'attributes', 'license').length).to eq 1
        expect(json.dig('data', 0, 'attributes', 'license')).to contain_exactly({
          'identifier' => 'CC-BY-NC-SA-4.0',
          'url' => 'https://creativecommons.org/licenses/by-nc-sa/4.0',
          'contentUrl' => nil,
        })
      end
    end
  end

  describe 'image' do
    let(:request_headers) { {'Accept' => 'application/vnd.api+json; moochub-version=3.0'} }
    let(:courses) { create_list(:course, 1) }

    it_behaves_like 'a successful request'

    it 'returns the course default image with default license if there is no visual image specified' do
      request
      expect(json.dig('data', 0, 'attributes', 'image')).to match({
        'type' => 'ImageObject',
        'contentUrl' => %r{\Ahttp://www\.example\.com/assets/defaults/course-[a-z0-9]+\.png},
        'license' => an_instance_of(Array),
      })
      expect(json.dig('data', 0, 'attributes', 'image', 'license')).to contain_exactly({
        'identifier' => 'CC0-1.0',
        'url' => 'https://creativecommons.org/publicdomain/zero/1.0',
        'contentUrl' => nil,
      })
    end

    context 'with course visual' do
      let(:courses) { create_list(:course, 1, :with_visual, image_uri: 's3://xikolo-public/courses/123/456/image.png') }

      it_behaves_like 'a successful request'

      it 'returns the visual with the default course license' do
        request
        expect(json.dig('data', 0, 'attributes', 'image')).to match({
          'type' => 'ImageObject',
          'contentUrl' => 'https://s3.xikolo.de/xikolo-public/courses/123/456/image.png',
          'license' => an_instance_of(Array),
        })
        expect(json.dig('data', 0, 'attributes', 'image', 'license')).to contain_exactly({
          'identifier' => 'CC-BY-NC-SA-4.0',
          'url' => 'https://creativecommons.org/licenses/by-nc-sa/4.0',
          'contentUrl' => nil,
        })
      end
    end

    context 'with course-specific license' do
      before { create(:metadata, :proprietary_license, course: courses.first) }

      it_behaves_like 'a successful request'

      it 'returns the course default image with default license if there is no visual image specified, i.e. ignores the course-specific license' do
        request
        expect(json.dig('data', 0, 'attributes', 'image')).to match({
          'type' => 'ImageObject',
          'contentUrl' => %r{\Ahttp://www\.example\.com/assets/defaults/course-[a-z0-9]+\.png},
          'license' => an_instance_of(Array),
        })
        expect(json.dig('data', 0, 'attributes', 'image', 'license')).to contain_exactly({
          'identifier' => 'CC0-1.0',
          'url' => 'https://creativecommons.org/publicdomain/zero/1.0',
          'contentUrl' => nil,
        })
      end

      context 'with course visual' do
        let(:courses) { create_list(:course, 1, :with_visual, image_uri: 's3://xikolo-public/courses/123/456/image.png') }

        it_behaves_like 'a successful request'

        it 'returns the visual with the configured course license' do
          request
          expect(json.dig('data', 0, 'attributes', 'image')).to match({
            'type' => 'ImageObject',
            'contentUrl' => 'https://s3.xikolo.de/xikolo-public/courses/123/456/image.png',
            'license' => an_instance_of(Array),
          })
          expect(json.dig('data', 0, 'attributes', 'image', 'license')).to contain_exactly({
            'identifier' => 'proprietary',
            'url' => nil,
            'contentUrl' => nil,
          })
        end
      end
    end
  end

  describe 'trailer' do
    let(:request_headers) { {'Accept' => 'application/vnd.api+json; moochub-version=3.0'} }
    let(:courses) { create_list(:course, 1, :with_teaser_video) }

    it_behaves_like 'a successful request'

    it 'returns the trailer with the default license' do
      request
      expect(json.dig('data', 0, 'attributes', 'trailer')).to match({
        'type' => 'VideoObject',
        'contentUrl' => 'http://player.vimeo.com/external/73209171.hd.mp4?s=9d2233269d6cbd749c78c80274f09387',
        'license' => an_instance_of(Array),
      })
      expect(json.dig('data', 0, 'attributes', 'trailer', 'license')).to contain_exactly({
        'identifier' => 'CC-BY-NC-SA-4.0',
        'url' => 'https://creativecommons.org/licenses/by-nc-sa/4.0',
        'contentUrl' => nil,
      })
    end

    context 'with course-specific license' do
      before { create(:metadata, :proprietary_license, course: courses.first) }

      it_behaves_like 'a successful request'

      it 'returns the course trailer with the configured course license' do
        request
        expect(json.dig('data', 0, 'attributes', 'trailer')).to match({
          'type' => 'VideoObject',
          'contentUrl' => 'http://player.vimeo.com/external/73209171.hd.mp4?s=9d2233269d6cbd749c78c80274f09387',
          'license' => an_instance_of(Array),
        })
        expect(json.dig('data', 0, 'attributes', 'trailer', 'license')).to contain_exactly({
          'identifier' => 'proprietary',
          'url' => nil,
          'contentUrl' => nil,
        })
      end
    end

    context 'without teaser video' do
      let(:courses) { create_list(:course, 1) }

      before { create(:metadata, :proprietary_license, course: courses.first) }

      it_behaves_like 'a successful request'

      it 'does not contain the trailer attribute' do
        request
        expect(json.dig('data', 0, 'attributes')).not_to have_key('trailer')
      end
    end
  end

  describe 'when the API is not enabled' do
    before do
      xi_config <<~YML
        moochub_api:
          enabled: false
      YML
    end

    it { expect { request }.to raise_error(AbstractController::ActionNotFound) }
  end

  describe '(pagination)' do
    context 'when another page exists' do
      let(:courses_1) { [build(:'course:course'), build(:'course:course'), build(:'course:course')] }
      let(:courses_2) { [build(:'course:course'), build(:'course:course')] }
      let(:stub_courses) do
        Stub.request(:course, :get, '/courses', query: hash_including(page: '1'))
          .to_return Stub.json(
            courses_1,
            links: {next: '/courses?p=2'},
            headers: {'X-Total-Pages' => 2, 'X-Current-Page' => 1}
          )

        Stub.request(:course, :get, '/courses', query: hash_including(page: '2'))
          .to_return Stub.json(
            courses_2,
            links: {prev: '/courses?p=1'},
            headers: {'X-Total-Pages' => 2, 'X-Current-Page' => 2}
          )
      end

      before do
        courses_1.pluck('id').each {|id| create(:course, id:) }
        courses_2.pluck('id').each {|id| create(:course, id:) }
      end

      it_behaves_like 'a successful request'

      it 'contains correct pagination links' do
        request
        expect(json['links']).to include(
          'self' => 'http://www.example.com/bridges/moochub/courses?page=1',
          'first' => 'http://www.example.com/bridges/moochub/courses?page=1',
          'last' => 'http://www.example.com/bridges/moochub/courses?page=2',
          'next' => 'http://www.example.com/bridges/moochub/courses?page=2'
        )
      end
    end

    context 'when there is a previous and a next page' do
      let(:courses_1) { [build(:'course:course'), build(:'course:course'), build(:'course:course')] }
      let(:courses_2) { [build(:'course:course'), build(:'course:course'), build(:'course:course')] }
      let(:courses_3) { [build(:'course:course'), build(:'course:course')] }
      let(:params) { {page: 2} }
      let(:stub_courses) do
        Stub.request(:course, :get, '/courses', query: hash_including(page: '1'))
          .to_return Stub.json(
            courses_1,
            links: {next: '/courses?p=2'},
            headers: {'X-Total-Pages' => 3, 'X-Current-Page' => 1}
          )

        Stub.request(:course, :get, '/courses', query: hash_including(page: '2'))
          .to_return Stub.json(
            courses_2,
            links: {prev: '/courses?p=1', next: '/courses?p=3'},
            headers: {'X-Total-Pages' => 3, 'X-Current-Page' => 2}
          )

        Stub.request(:course, :get, '/courses', query: hash_including(page: '3'))
          .to_return Stub.json(
            courses_3,
            links: {prev: '/courses?p=2'},
            headers: {'X-Total-Pages' => 3, 'X-Current-Page' => 3}
          )
      end

      before do
        courses_1.pluck('id').each {|id| create(:course, id:) }
        courses_2.pluck('id').each {|id| create(:course, id:) }
        courses_3.pluck('id').each {|id| create(:course, id:) }
      end

      it_behaves_like 'a successful request'

      it 'contains correct pagination links' do
        request
        expect(json['links']).to include(
          'self' => 'http://www.example.com/bridges/moochub/courses?page=2',
          'first' => 'http://www.example.com/bridges/moochub/courses?page=1',
          'last' => 'http://www.example.com/bridges/moochub/courses?page=3',
          'prev' => 'http://www.example.com/bridges/moochub/courses?page=1',
          'next' => 'http://www.example.com/bridges/moochub/courses?page=3'
        )
      end
    end
  end
end
