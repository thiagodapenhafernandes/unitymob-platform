class LinkedinIntegration < ApplicationRecord
  include TenantScoped
  include EncryptionAvailability

  belongs_to :admin_user
  encrypts :access_token
  validates :tenant_id, uniqueness: true
  validate do
    errors.add(:admin_user, "deve pertencer à conta") if admin_user && admin_user.tenant_id != tenant_id
  end

  def self.configured?
    encryption_ready? && %w[LINKEDIN_CLIENT_ID LINKEDIN_CLIENT_SECRET LINKEDIN_REDIRECT_URI].all? { |key| ENV[key].present? }
  end

  def connected?
    encryption_ready? && access_token.present? && token_expires_at.present? && token_expires_at.future?
  end

  def campaign_structure
    return {} unless connected?

    catalog.select { |_id, campaign| selected_account_ids.include?(campaign["account_id"]) }
  end

  def form_ids_for(campaign_ids)
    campaign_structure.slice(*campaign_ids).values.flat_map { |campaign| Array(campaign["forms"]).pluck("id") }.uniq
  end
end
