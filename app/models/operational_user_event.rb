class OperationalUserEvent < ApplicationRecord
  EVENT_NAMES = %w[
    property_list_viewed
    catalog_search
    property_opened
    ai_text_search
    ai_voice_search
    ai_property_selected
    selection_shared
  ].freeze

  EVENT_LABELS = {
    "property_list_viewed" => "Listagem visualizada",
    "catalog_search" => "Pesquisa no catálogo",
    "property_opened" => "Imóvel aberto",
    "ai_text_search" => "Busca IA por texto",
    "ai_voice_search" => "Busca IA por voz",
    "ai_property_selected" => "Imóvel selecionado na busca IA",
    "selection_shared" => "Seleção compartilhada"
  }.freeze

  include TenantScoped

  belongs_to :admin_user
  belongs_to :operational_user_session
  belongs_to :habitation, optional: true

  validates :name, presence: true, inclusion: { in: EVENT_NAMES }
  validates :occurred_at, presence: true
  validate :tenant_consistency

  before_validation :set_defaults

  scope :recent, -> { order(occurred_at: :desc, id: :desc) }
  scope :property_views, -> { where(name: %w[property_opened ai_property_selected]) }
  scope :searches, -> { where(name: %w[catalog_search ai_text_search ai_voice_search]) }

  def event_label
    EVENT_LABELS[name] || name.to_s.humanize
  end

  def visible_count
    Array(visible_habitation_ids).size
  end

  private

  def set_defaults
    self.occurred_at ||= Time.current
    self.filter_params = {} unless filter_params.is_a?(Hash)
    self.visible_habitation_ids = [] unless visible_habitation_ids.is_a?(Array)
    self.metadata = {} unless metadata.is_a?(Hash)
  end

  def tenant_consistency
    errors.add(:admin_user, "não pertence à conta") if admin_user && admin_user.tenant_id != tenant_id
    if operational_user_session && operational_user_session.tenant_id != tenant_id
      errors.add(:operational_user_session, "não pertence à conta")
    end
    errors.add(:habitation, "não pertence à conta") if habitation && habitation.tenant_id != tenant_id
  end
end
