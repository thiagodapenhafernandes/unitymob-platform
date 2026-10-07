class TiktokIntegration < ApplicationRecord
  include TenantScoped
  include EncryptionAvailability

  belongs_to :admin_user
  encrypts :access_token
  before_validation { self.route_key ||= SecureRandom.uuid }
  validates :tenant_id, :route_key, uniqueness: true
  validate do
    errors.add(:admin_user, "deve pertencer à conta") if admin_user && admin_user.tenant_id != tenant_id
  end

  def self.configured?
    encryption_ready? && %w[TIKTOK_APP_ID TIKTOK_APP_SECRET TIKTOK_REDIRECT_URI].all? { |key| ENV[key].present? } && Tiktok::GatewayClient.configured?
  end

  def connected?
    encryption_ready? && access_token.present?
  end

  def form_structure
    return {} unless connected?
    catalog.slice(*selected_account_ids)
  end
end
