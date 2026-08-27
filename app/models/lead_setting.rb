class LeadSetting < ApplicationRecord
  include TenantScoped
  MATCHES   = %w[phone phone_or_email phone_and_email].freeze
  OWNERS    = %w[attended any_assignment].freeze
  FALLBACKS = %w[active_in_rule active_any].freeze
  # Destino do clique na notificação de novo lead (dentro do prazo do pocket).
  PUSH_CLICK_ACTIONS = %w[system whatsapp].freeze
  DEFAULT_FIRST_CONTACT_SLA_HOURS = 4
  DEFAULT_STAGE_AUTOMATION_SWEEP_INTERVAL_MINUTES = 15
  MIN_STAGE_AUTOMATION_SWEEP_INTERVAL_MINUTES = 5
  MAX_STAGE_AUTOMATION_SWEEP_INTERVAL_MINUTES = 1440

  # Status que contam como "atendido de fato" pelo corretor (owner = attended).
  ATTENDED_STATUSES = %i[em_atendimento concluido].freeze

  validates :stickiness_match,    inclusion: { in: MATCHES }
  validates :stickiness_owner,    inclusion: { in: OWNERS }
  validates :stickiness_fallback, inclusion: { in: FALLBACKS }
  validates :stickiness_window_days,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true
  validates :secure_link_expiry_days,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :first_contact_sla_hours,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 168 }
  validates :stage_automation_sweep_interval_minutes,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: MIN_STAGE_AUTOMATION_SWEEP_INTERVAL_MINUTES,
              less_than_or_equal_to: MAX_STAGE_AUTOMATION_SWEEP_INTERVAL_MINUTES
            }
  validates :push_lead_click_action, inclusion: { in: PUSH_CLICK_ACTIONS }

  # Singleton.
  def self.instance(tenant: Current.tenant)
    raise ArgumentError, "Tenant obrigatório para configurações de leads" if tenant.blank?

    where(tenant: tenant).first_or_create!
  end

  def stickiness_enabled?
    stickiness_enabled
  end

  def match_phone?
    stickiness_match == "phone"
  end

  def match_email_too?
    %w[phone_or_email phone_and_email].include?(stickiness_match)
  end

  def owner_attended_only?
    stickiness_owner == "attended"
  end

  def fallback_in_rule?
    stickiness_fallback == "active_in_rule"
  end

  def window_forever?
    stickiness_window_days.to_i <= 0
  end

  def attended_status_values
    ATTENDED_STATUSES.map { |s| Lead.status_value(s) }.uniq
  end

  def first_contact_sla_hours_value
    first_contact_sla_hours.presence || DEFAULT_FIRST_CONTACT_SLA_HOURS
  end

  def stage_automation_sweep_interval_minutes_value
    stage_automation_sweep_interval_minutes.presence || DEFAULT_STAGE_AUTOMATION_SWEEP_INTERVAL_MINUTES
  end

  def stage_automation_sweep_due?(now: Time.current)
    stage_automation_last_swept_at.blank? ||
      stage_automation_last_swept_at <= stage_automation_sweep_interval_minutes_value.minutes.ago(now)
  end

  def push_lead_click_action_value
    push_lead_click_action.presence_in(PUSH_CLICK_ACTIONS) || "system"
  end

  def open_whatsapp_on_click?
    push_lead_click_action_value == "whatsapp"
  end
end
