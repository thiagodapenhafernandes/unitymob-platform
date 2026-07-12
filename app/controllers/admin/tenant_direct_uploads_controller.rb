class Admin::TenantDirectUploadsController < ActiveStorage::DirectUploadsController
  before_action :authenticate_admin_user!
  before_action :require_tenant!

  private

  def blob_args
    super.tap do |attributes|
      attributes[:metadata] = attributes.fetch(:metadata, {}).merge("tenant_id" => current_admin_user.tenant_id)
    end
  end

  def require_tenant!
    head :forbidden if current_admin_user&.tenant_id.blank?
  end
end
