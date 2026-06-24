class LeadSetting < ApplicationRecord
  MATCHES   = %w[phone phone_or_email phone_and_email].freeze
  OWNERS    = %w[attended any_assignment].freeze
  FALLBACKS = %w[active_in_rule active_any].freeze

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
end
