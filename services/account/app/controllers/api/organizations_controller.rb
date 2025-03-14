# frozen_string_literal: true

class API::OrganizationsController < API::RESTController
  respond_to :json

  def create
    respond_with Organization.create(organization_params), status: :created
  end

  def update
    resource.update organization_params
    respond_with resource
  end

  def destroy
    respond_with resource.destroy!
  end

  private

  def organization_params
    params.permit(:name)
  end
end
