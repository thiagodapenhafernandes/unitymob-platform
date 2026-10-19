class Ga4ConversionConfig < ApplicationRecord
  include TenantScoped
  include EncryptionAvailability

  encrypts :api_secret

  validates :tenant_id, uniqueness: true
  validates :measurement_id, format: { with: /\AG-[A-Z0-9]+\z/ }, allow_blank: true
  validates :measurement_id, :api_secret, :activated_at, presence: true, if: :enabled?

  def active?
    enabled? && encryption_ready? && measurement_id.present? && api_secret.present? && activated_at.present? && activated_at <= Time.current
  rescue ActiveRecord::Encryption::Errors::Base
    false
  end
end
