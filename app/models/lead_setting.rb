class LeadSetting < ApplicationRecord
  MATCHES   = %w[phone phone_or_email phone_and_email].freeze
  OWNERS    = %w[attended any_assignment].freeze
  FALLBACKS = %w[active_in_rule active_any].freeze
  PUSH_CLICK_ACTIONS = PushSetting::LEAD_CLICK_ACTIONS.freeze

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
  validates :push_lead_click_action, inclusion: { in: PUSH_CLICK_ACTIONS }

  # Singleton.
  def self.instance
    first_or_create!
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

  # Configuração operacional do push, persistida em PushSetting para manter as
  # credenciais VAPID e o comportamento do clique em uma única tabela técnica.
  def push_lead_click_action
    return @push_lead_click_action if instance_variable_defined?(:@push_lead_click_action)

    PushSetting.instance.lead_click_action_value
  rescue ActiveRecord::StatementInvalid
    "system"
  end

  def push_lead_click_action=(value)
    @push_lead_click_action = value.to_s
  end
end
