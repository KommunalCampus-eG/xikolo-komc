# frozen_string_literal: true

class Admin::OrganizationsController < Abstract::FrontendController
  require_permission 'account.organizations.manage'

  def index
    @organizations = Account::Organization.order(:name).paginate(page: params[:page] || 1, per_page: 50)
  end

  def new
    @organization = Account::Organization.new
  end

  def edit
    @organization = Account::Organization.find(params[:id])
  end

  def create
    account_api.rel(:organizations).post(organization_params.to_h).value!
    add_flash_message :success, I18n.t(:'flash.success.organization_created')
    redirect_to admin_organizations_path
  rescue Restify::ClientError
    add_flash_message :error, I18n.t(:'flash.error.organization_not_created')
    redirect_to admin_organizations_path
  end

  def update
    account_api.rel(:organization).patch(organization_params.to_h, id: params[:id]).value!
    add_flash_message :success, I18n.t(:'flash.success.organization_updated')
    redirect_to admin_organizations_path
  rescue Restify::ClientError
    add_flash_message :error, I18n.t(:'flash.error.organization_not_updated')
    redirect_to admin_organizations_path
  end

  def destroy
    account_api.rel(:organization).delete(id: params[:id]).value!
    add_flash_message :success, I18n.t(:'flash.success.organization_deleted')
    redirect_to admin_organizations_path
  rescue Restify::ClientError
    add_flash_message :error, I18n.t(:'flash.error.organization_not_deleted')
    redirect_to admin_organizations_path
  end

  def export
    organizations = Account::Organization.order(:name)

    csv_data = CSV.generate(col_sep: ';') do |csv|
      organizations.each do |organization|
        csv << [organization.name]
      end
    end

    send_data(
      csv_data,
      filename: 'organizations.csv',
      type: 'text/csv',
      disposition: 'attachment'
    )
  end

  private

  def organization_params
    params.require(:account_organization).permit(:name)
  end

  def account_api
    @account_api ||= Xikolo.api(:account).value!
  end
end
