# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Admin::OrganizationsController, type: :controller do
  let(:user_id) { SecureRandom.uuid }
  let(:permissions) { ['account.organizations.manage'] }
  let(:organization_id) { SecureRandom.uuid }
  let(:organization) { create(:organization) }

  before do
    stub_user(id: user_id, language: 'en', permissions:)

    Stub.service(:account,
      session_url: '/sessions/{id}',
      organizations_url: '/organizations',
      organization_url: '/organizations/{id}')
  end

  describe 'GET index' do
    let(:params) { {page: '1'} }

    it 'answers with a page' do
      get :index, params: params
      expect(response).to be_successful
      expect(response).to render_template(:index)
    end

    context 'without account.organizations.manage permission' do
      let(:permissions) { [] }

      it 'cannot access the page' do
        get :index, params: params
        expect(response).to redirect_to root_url
      end
    end
  end

  describe 'GET new' do
    it 'answers with a page' do
      get :new
      expect(response).to be_successful
      expect(response).to render_template(:new)
    end

    context 'without account.organizations.manage permission' do
      let(:permissions) { [] }

      it 'cannot access the page' do
        get :new
        expect(response).to redirect_to root_url
      end
    end
  end

  describe 'GET edit' do
    let(:params) { {id: organization.id} }

    it 'finds the organization and renders the edit template' do
      get :edit, params: params
      expect(response).to be_successful
      expect(response).to render_template(:edit)
    end

    context 'without account.organizations.manage permission' do
      let(:permissions) { [] }

      it 'cannot access the page' do
        get :edit, params: params
        expect(response).to redirect_to root_url
      end
    end
  end

  describe 'POST create' do
    let(:params) { {name: 'New Organization'} }

    context 'when the API request is successful' do
      before do
        Stub.request(
          :account, :post, '/organizations'
        ).to_return Stub.json(organization)
      end

      it 'creates a organization and redirects with success message' do
        post :create, params: {account_organization: params}
        expect(response).to redirect_to(admin_organizations_path)
        expect(flash[:success].first).to eq(I18n.t(:'flash.success.organization_created'))
      end
    end

    context 'when the API request fails' do
      before do
        Stub.request(
          :account, :post, '/organizations'
        ).to_return(status: 400, body: {errors: ['Invalid organization name']}.to_json)
      end

      it 'redirects with an error message' do
        post :create, params: {account_organization: params}
        expect(response).to redirect_to(admin_organizations_path)
        expect(flash[:error].first).to eq(I18n.t(:'flash.error.organization_not_created'))
      end
    end

    context 'without account.organizations.manage permission' do
      let(:permissions) { [] }

      it 'cannot access the page' do
        post :create, params: {account_organization: params}
        expect(response).to redirect_to root_url
      end
    end
  end

  describe 'PATCH update' do
    let(:params) { {name: 'Updated Organization'} }

    context 'when the API request is successful' do
      before do
        Stub.request(
          :account, :patch, "/organizations/#{organization_id}"
        ).to_return Stub.json(organization)
      end

      it 'updates the organization and redirects with success message' do
        patch :update, params: {id: organization_id, account_organization: params}
        expect(response).to redirect_to(admin_organizations_path)
        expect(flash[:success].first).to eq(I18n.t(:'flash.success.organization_updated'))
      end
    end

    context 'when the API request fails' do
      before do
        Stub.request(
          :account, :patch, "/organizations/#{organization_id}"
        ).to_return(status: 400, body: {errors: ['Invalid organization name']}.to_json)
      end

      it 'redirects with an error message' do
        patch :update, params: {id: organization_id, account_organization: params}
        expect(response).to redirect_to(admin_organizations_path)
        expect(flash[:error].first).to eq(I18n.t(:'flash.error.organization_not_updated'))
      end
    end

    context 'without account.organizations.manage permission' do
      let(:permissions) { [] }

      it 'cannot access the page' do
        patch :update, params: {id: organization_id, account_organization: params}
        expect(response).to redirect_to root_url
      end
    end
  end

  describe 'DELETE destroy' do
    let(:params) { {id: organization_id} }

    context 'when the API request is successful' do
      before do
        Stub.request(
          :account, :delete, "/organizations/#{organization_id}"
        ).to_return Stub.json(organization)
      end

      it 'deletes the organization and redirects with success message' do
        delete :destroy, params: params
        expect(response).to redirect_to(admin_organizations_path)
        expect(flash[:success].first).to eq(I18n.t(:'flash.success.organization_deleted'))
      end
    end

    context 'when the API request fails' do
      before do
        Stub.request(
          :account, :delete, "/organizations/#{organization_id}"
        ).to_return(status: 404, body: {errors: ['The organization was not found']}.to_json)
      end

      it 'redirects with an error message' do
        delete :destroy, params: params
        expect(response).to redirect_to(admin_organizations_path)
        expect(flash[:error].first).to eq(I18n.t(:'flash.error.organization_not_deleted'))
      end
    end

    context 'without account.organizations.manage permission' do
      let(:permissions) { [] }

      it 'cannot access the page' do
        delete :destroy, params: params
        expect(response).to redirect_to root_url
      end
    end
  end

  describe 'GET export' do
    it 'answers with a csv attachment' do
      get :export

      expect(response).to be_successful
      expect(response.headers['Content-Type']).to eq('text/csv')
      expect(response.headers['Content-Disposition']).to include('attachment')
    end

    context 'without account.organizations.manage permission' do
      let(:permissions) { [] }

      it 'cannot access the page' do
        get :export
        expect(response).to redirect_to root_url
      end
    end
  end
end
