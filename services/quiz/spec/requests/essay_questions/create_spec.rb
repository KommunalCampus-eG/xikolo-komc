# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Essay Questions: Create', type: :request do
  subject(:resource) { api.rel(:essay_questions).post(params).value! }

  let(:api) { Restify.new(:test).get.value! }

  let(:params) { attributes_for(:essay_question, quiz_id: quiz.id) }
  let(:quiz) { create(:quiz) }

  before do
    Stub.service(
      :course,
      items_url: 'http://course.xikolo.tld/items',
      item_url: 'http://course.xikolo.tld/items/{id}'
    )
    Stub.request(
      :course, :get, '/items',
      query: {content_id: params[:quiz_id]}
    ).to_return Stub.json([
      {id: '53d99410-28c1-4516-8ef5-49ed0e593918'},
    ])
    Stub.request(
      :course, :patch, '/items/53d99410-28c1-4516-8ef5-49ed0e593918',
      body: hash_including(max_points: params[:points])
    ).to_return Stub.json({max_points: params[:points]})
  end

  it { is_expected.to respond_with :created }

  it 'creates a new essay question' do
    expect { resource }.to change(EssayQuestion, :count).from(0).to(1)
  end

  context 'without a type attribute' do
    let(:params) { super().except(:type) }

    it 'creates a new essay question' do
      expect { resource }.to change(EssayQuestion, :count).from(0).to(1)
    end
  end
end
