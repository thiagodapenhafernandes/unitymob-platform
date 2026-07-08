class AccessAuditLog < ApplicationRecord
  include TenantScoped

  EVENT_TYPES = %w[login logout admin_access access_denied impersonation_start impersonation_stop
                   two_factor_challenge two_factor_success two_factor_failed two_factor_enabled two_factor_disabled
                   account_switch membership_invited membership_accepted membership_revoked].freeze
  RESULTS = %w[allowed denied].freeze

  EVENT_LABELS = {
    "login" => "Login",
    "logout" => "Logout",
    "admin_access" => "Acesso administrativo",
    "access_denied" => "Acesso negado",
    "impersonation_start" => "Início de impersonação",
    "impersonation_stop" => "Fim de impersonação",
    "two_factor_challenge" => "Desafio 2FA emitido",
    "two_factor_success" => "2FA verificado",
    "two_factor_failed" => "2FA falhou",
    "two_factor_enabled" => "2FA ativado",
    "two_factor_disabled" => "2FA desativado",
    "account_switch" => "Troca de conta",
    "membership_invited" => "Convite externo enviado",
    "membership_accepted" => "Convite externo aceito",
    "membership_revoked" => "Acesso externo revogado"
  }.freeze

  RESULT_LABELS = {
    "allowed" => "Permitido",
    "denied" => "Negado"
  }.freeze

  belongs_to :admin_user, optional: true

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :result, presence: true, inclusion: { in: RESULTS }
  validate :admin_user_tenant_consistency

  self.record_timestamps = false
  before_create :set_created_at

  scope :recent, -> { order(created_at: :desc) }
  scope :denied, -> { where(result: "denied") }
  scope :allowed, -> { where(result: "allowed") }

  def readonly?
    persisted?
  end

  def self.log!(event_type:, result:, request:, admin_user: nil, email: nil, reason: nil, metadata: {})
    device = AccessAudit::DeviceParser.call(request&.user_agent.to_s)

    create!(
      event_type: event_type,
      result: result,
      admin_user: admin_user,
      email: email.presence || admin_user&.email,
      reason: reason,
      ip: request&.remote_ip,
      user_agent: request&.user_agent.to_s.first(255),
      device_type: device[:device_type],
      browser: device[:browser],
      platform: device[:platform],
      path: request&.fullpath.to_s.first(255),
      request_method: request&.request_method,
      controller_name: request&.params&.[](:controller),
      action_name: request&.params&.[](:action),
      metadata: metadata.compact
    )
  rescue => e
    Rails.logger.warn("[AccessAuditLog] #{e.class}: #{e.message}")
    nil
  end

  def actor_name
    tenant_admin_user&.name.presence || email.presence || "Usuário não identificado"
  end

  def tenant_optional?
    admin_user.blank? || admin_user.system_admin?
  end

  def event_label
    EVENT_LABELS[event_type] || event_type.to_s.humanize
  end

  def result_label
    RESULT_LABELS[result] || result.to_s.humanize
  end

  def device_label
    [device_type, browser, platform].compact_blank.join(" · ").presence || "Dispositivo não identificado"
  end

  private

  def set_created_at
    self.created_at ||= Time.current
  end

  def tenant_admin_user
    return if admin_user_id.blank?
    return admin_user if tenant_id.blank? && admin_user&.system_admin?
    return if tenant.blank?

    tenant.admin_users.find_by(id: admin_user_id)
  end

  def admin_user_tenant_consistency
    return if admin_user.blank?

    if admin_user.system_admin?
      errors.add(:tenant, "deve ficar vazio para log de Admin do Sistema") if tenant_id.present?
    elsif tenant_id.blank?
      errors.add(:tenant, "deve estar presente para log de usuário da conta")
    elsif admin_user.tenant_id != tenant_id
      errors.add(:admin_user, "deve pertencer ao mesmo Tenant")
    end
  end
end
