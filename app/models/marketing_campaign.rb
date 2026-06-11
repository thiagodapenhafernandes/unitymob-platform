class MarketingCampaign < ApplicationRecord
  CHANNELS = {
    "organic" => "Orgânico",
    "google_ads" => "Google Ads",
    "meta_ads" => "Meta Ads",
    "instagram" => "Instagram",
    "whatsapp" => "WhatsApp",
    "footer" => "Rodapé",
    "home" => "Home"
  }.freeze

  STATUSES = {
    "idea" => "Ideia",
    "planned" => "Planejada",
    "active" => "Ativa",
    "paused" => "Pausada",
    "finished" => "Concluída"
  }.freeze

  belongs_to :seo_setting, optional: true
  belongs_to :admin_user, optional: true
  has_many :seo_conversion_events, dependent: :nullify

  validates :name, presence: true
  validates :channel, inclusion: { in: CHANNELS.keys }
  validates :status, inclusion: { in: STATUSES.keys }
  validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }

  before_validation :fill_target_url_from_seo
  before_validation :ensure_slug
  before_validation :ensure_utm_campaign

  after_initialize :set_default_utm_fields, if: :new_record?

  scope :recent, -> { order(updated_at: :desc) }
  scope :active_or_planned, -> { where(status: %w[active planned idea]) }

  def channel_label
    CHANNELS[channel] || channel.to_s.humanize
  end

  def status_label
    STATUSES[status] || status.to_s.humanize
  end

  def status_badge_class
    case status
    when "active" then "success"
    when "planned" then "primary"
    when "idea" then "info"
    when "paused" then "warning"
    when "finished" then "secondary"
    else "dark"
    end
  end

  def budget
    budget_cents.to_i / 100.0
  end

  def budget=(value)
    self.budget_cents = (value.to_s.gsub(/[^\d,\.]/, "").tr(",", ".").to_f.round(2) * 100).to_i
  end

  def generated_url(base_url = nil)
    return "" if target_url.blank?

    uri = URI.parse(absolute_target_url(base_url))
    params = Rack::Utils.parse_nested_query(uri.query)
    utm_params.each { |key, value| params[key] = value if value.present? }
    uri.query = params.to_query.presence
    uri.to_s
  rescue URI::InvalidURIError
    target_url.to_s
  end

  def utm_params
    {
      "utm_source" => utm_source.presence || channel.presence,
      "utm_medium" => utm_medium.presence || channel.presence,
      "utm_campaign" => utm_campaign.presence || slug.presence || name.to_s.parameterize,
      "utm_term" => utm_term,
      "utm_content" => utm_content
    }
  end

  def conversion_rate
    return 0.0 if clicks_count.to_i.zero?

    ((conversions_count.to_f / clicks_count.to_i) * 100).round(1)
  end

  def cost_per_conversion
    return 0.0 if conversions_count.to_i.zero?

    (budget / conversions_count.to_i).round(2)
  end

  def register_click!
    increment!(:clicks_count)
    update_column(:last_clicked_at, Time.current)
  end

  def register_conversion!
    increment!(:conversions_count)
  end

  private

  def fill_target_url_from_seo
    self.target_url = seo_setting&.sanitized_canonical_path if target_url.blank? && seo_setting.present?
  end

  def ensure_slug
    return if slug.present? || name.blank?

    base_slug = name.to_s.parameterize.presence || "campanha"
    candidate = base_slug
    suffix = 2

    while self.class.where(slug: candidate).where.not(id: id).exists?
      candidate = "#{base_slug}-#{suffix}"
      suffix += 1
    end

    self.slug = candidate
  end

  def ensure_utm_campaign
    self.utm_campaign = slug if utm_campaign.blank? && slug.present?
  end

  def set_default_utm_fields
    self.utm_source ||= channel.presence || "organic"
    self.utm_medium ||= channel.presence || "organic"
  end

  def absolute_target_url(base_url)
    return target_url if target_url.to_s.start_with?("http://", "https://")
    return target_url if base_url.blank?

    "#{base_url.to_s.delete_suffix("/")}#{target_url.to_s.start_with?("/") ? target_url : "/#{target_url}"}"
  end
end
