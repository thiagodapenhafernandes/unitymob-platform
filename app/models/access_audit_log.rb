class AccessAuditLog < ApplicationRecord
  EVENT_TYPES = %w[login logout admin_access access_denied impersonation_start impersonation_stop].freeze
  RESULTS = %w[allowed denied].freeze

  EVENT_LABELS = {
    "login" => "Login",
    "logout" => "Logout",
    "admin_access" => "Acesso administrativo",
    "access_denied" => "Acesso negado",
    "impersonation_start" => "Início de impersonação",
    "impersonation_stop" => "Fim de impersonação"
  }.freeze

  RESULT_LABELS = {
    "allowed" => "Permitido",
    "denied" => "Negado"
  }.freeze

  belongs_to :admin_user, optional: true

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :result, presence: true, inclusion: { in: RESULTS }

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
    admin_user&.name.presence || email.presence || "Usuário não identificado"
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
end
