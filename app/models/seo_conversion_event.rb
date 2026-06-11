class SeoConversionEvent < ApplicationRecord
  EVENT_TYPES = {
    "lead_created" => "Lead criado",
    "schedule_visit" => "Visita agendada",
    "share_click" => "Clique em link de corretor",
    "campaign_click" => "Clique de campanha",
    "footer_click" => "Clique no rodapé",
    "property_card_click" => "Clique em card de imóvel",
    "whatsapp_click" => "Clique no WhatsApp",
    "cta_click" => "Clique em CTA"
  }.freeze

  belongs_to :seo_setting, optional: true
  belongs_to :marketing_campaign, optional: true
  belongs_to :lead, optional: true
  belongs_to :habitation, optional: true

  validates :event_type, presence: true
  validates :occurred_at, presence: true

  scope :recent, -> { order(occurred_at: :desc) }

  def event_label
    EVENT_TYPES[event_type] || event_type.to_s.humanize
  end
end
