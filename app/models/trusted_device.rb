class TrustedDevice < ApplicationRecord
  include TenantScoped

  belongs_to :tenant, optional: true

  STATUSES = {
    "pending" => "Pendente",
    "trusted" => "Confiável",
    "blocked" => "Bloqueado"
  }.freeze

  belongs_to :admin_user
  belongs_to :created_by, class_name: "AdminUser", optional: true

  validates :fingerprint, :status, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
  validates :fingerprint, uniqueness: { scope: [:tenant_id, :admin_user_id] }
  validate :admin_user_tenant_consistency
  validate :created_by_tenant_consistency

  scope :recent, -> { order(last_seen_at: :desc, created_at: :desc) }
  scope :pending, -> { where(status: "pending") }
  scope :trusted, -> { where(status: "trusted") }
  scope :blocked, -> { where(status: "blocked") }

  def status_label
    STATUSES[status] || status.to_s.humanize
  end

  def device_label
    [device_type, browser, platform].compact_blank.join(" · ").presence || "Dispositivo não identificado"
  end

  def tenant_optional?
    admin_user&.system_admin?
  end

  def trust!(actor = nil)
    update!(status: "trusted", trusted_at: Time.current, created_by: actor || created_by)
  end

  def block!(actor = nil)
    update!(status: "blocked", created_by: actor || created_by)
  end

  private

  def admin_user_tenant_consistency
    return if admin_user.blank?

    if admin_user.system_admin?
      errors.add(:tenant, "deve ficar vazio para dispositivo de plataforma") if tenant_id.present?
    elsif tenant_id.blank?
      errors.add(:tenant, "deve estar presente para dispositivo de usuário da conta")
    elsif admin_user.tenant_id != tenant_id
      errors.add(:admin_user, "deve pertencer ao mesmo Tenant")
    end
  end

  def created_by_tenant_consistency
    return if created_by&.system_admin?

    errors.add(:created_by, "deve pertencer ao mesmo Tenant") if created_by.present? && created_by.tenant_id != tenant_id
  end
end
