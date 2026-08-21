class ExternalLeadIntegration < ApplicationRecord
  include TenantScoped

  STATUSES = %w[disconnected connected failed inactive].freeze
  SYNC_STATUSES = %w[idle processing completed failed].freeze
  SUPPORT_RULE_NAME = "Migração de leads - distribuição espelhada".freeze
  WEBHOOK_TAG = "external_lead_migration".freeze
  LEAD_ORIGIN = "Migração externa".freeze
  LEGACY_TRASH_LOCAL_EMAIL = "lixeira@conexaobc.com.br".freeze
  LEGACY_TRASH_SELLER_EMAILS = %w[lixeira_cbc2025@c2sglobal.com].freeze
  LEGACY_TRASH_SELLER_NAMES = ["lixeira conexao bc"].freeze

  belongs_to :distribution_rule, optional: true
  belongs_to :connected_by_admin_user, class_name: "AdminUser", optional: true
  has_many :leads, dependent: :nullify

  before_validation :ensure_webhook_token

  validates :status, inclusion: { in: STATUSES }
  validates :sync_status, inclusion: { in: SYNC_STATUSES }
  validates :tenant_id, uniqueness: true
  validates :webhook_token, presence: true, uniqueness: true

  scope :enabled, -> { where(enabled: true, status: "connected") }

  def self.current(tenant)
    raise ArgumentError, "Tenant obrigatório para integração de leads" if tenant.blank?

    find_or_initialize_by(tenant: tenant)
  end

  def token_preview
    return nil if access_token.blank?

    "..." + access_token.last(6)
  end

  def connected?
    enabled? && status == "connected" && access_token.present?
  end

  def webhook_subscription_active?(hook_url = nil)
    connected? &&
      webhook_listening_enabled? &&
      subscribed_at.present? &&
      webhook_url.present? &&
      (hook_url.blank? || webhook_url == hook_url)
  end

  def mark_failed!(message)
    update!(
      status: access_token.present? ? "failed" : "disconnected",
      sync_status: "failed",
      sync_message: message.to_s.truncate(255),
      last_error_message: message
    )
  end

  def local_user_for_seller(seller)
    seller = seller.to_h
    mapped_id = seller_mappings[seller["id"].to_s].presence
    mapped_user = tenant.admin_users.active.find_by(id: mapped_id) if mapped_id
    return mapped_user if mapped_user

    email = seller["email"].to_s.strip.downcase
    if email.present?
      email_user = tenant.admin_users.active.find_by("lower(email) = ?", email)
      return email_user if email_user
    end

    phone = Phones::Normalizer.call(seller["phone"])
    if phone.present?
      phone_user = tenant.admin_users.active.detect do |admin_user|
        Phones::Normalizer.call(admin_user.phone) == phone ||
          (admin_user.respond_to?(:secondary_phone) && Phones::Normalizer.call(admin_user.secondary_phone) == phone)
      end
      return phone_user if phone_user
    end

    legacy_trash_user_for(seller)
  end

  private

  def ensure_webhook_token
    self.webhook_token = SecureRandom.urlsafe_base64(32) if webhook_token.blank?
  end

  def legacy_trash_user_for(seller)
    return unless legacy_trash_seller?(seller)

    tenant.admin_users.active.find_by("lower(email) = ?", LEGACY_TRASH_LOCAL_EMAIL)
  end

  def legacy_trash_seller?(seller)
    email = seller["email"].to_s.strip.downcase
    name = seller["name"].to_s.parameterize(separator: " ")

    LEGACY_TRASH_SELLER_EMAILS.include?(email) || LEGACY_TRASH_SELLER_NAMES.include?(name)
  end
end
