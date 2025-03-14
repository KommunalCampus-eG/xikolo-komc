# frozen_string_literal: true

require 'spec_helper'

describe API::OrganizationsController, type: :controller do
  let(:params) { {} }
  let(:organization) { create(:organization) }

  before { organization }

  describe '#create' do
    subject(:response) { post :create, params: }

    let(:params) { {name: 'Organization A'} }

    it { expect { response }.to change(Organization, :count).by(1) }
    it { is_expected.to have_http_status :created }

    describe 'JSON' do
      subject(:json) { JSON.parse(response.body) }

      it 'is the created organization record' do
        expect(json).to include \
          'id',
          'name' => params[:name]
      end
    end
  end

  describe '#update' do
    subject(:response) { patch :update, params: }

    let(:params) { {id: organization.id, name: 'Organization Updated'} }

    it { is_expected.to have_http_status :ok }

    it 'updates the organization record' do
      response
      expect(organization.reload.name).to eq(params[:name])
    end

    describe 'JSON' do
      subject(:json) { JSON.parse(response.body) }

      it 'is the updated organization record' do
        expect(json).to include \
          'id' => organization.id,
          'name' => params[:name]
      end
    end
  end

  describe '#destroy' do
    subject(:response) { delete :destroy, params: }

    let(:params) { {id: organization.id} }

    it { is_expected.to have_http_status :ok }

    it 'deletes the organization record' do
      expect { response }.to change(Organization, :count).from(1).to(0)
    end

    describe 'JSON' do
      subject(:json) { JSON.parse(response.body) }

      it 'is the deleted organization record' do
        expect(json).to include \
          'id' => organization.id,
          'name' => organization.name
      end
    end
  end
end
