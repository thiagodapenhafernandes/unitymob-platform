class LeadPipeline < ApplicationRecord
  include TenantScoped

  KINDS = {
    "sale" => "Venda",
    "rental" => "Locação",
    "daily" => "Diária",
    "mixed" => "Venda e locação",
    "custom" => "Sem tipo específico"
  }.freeze

  DEFAULT_STAGE_DEFINITIONS = [
    { name: "Novo Lead", stage_type: "open", color: "#2f80a0" },
    { name: "Em Atendimento", stage_type: "open", color: "#365f8f" },
    { name: "Visita/Contato", stage_type: "open", color: "#8a63d2" },
    { name: "Proposta", stage_type: "open", color: "#d97706" },
    { name: "Ganho", stage_type: "won", color: "#08875d" },
    { name: "Perdido", stage_type: "lost", color: "#e0402f" },
    { name: "Arquivado", stage_type: "archived", color: "#667085" }
  ].freeze

  belongs_to :tenant
  has_many :stages, class_name: "LeadPipelineStage", dependent: :destroy
  has_many :leads, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :tenant_id, case_sensitive: false }
  validates :kind, inclusion: { in: KINDS.keys }
  validate :single_default_per_kind

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(Arel.sql("position ASC NULLS LAST"), :name) }

  before_validation :assign_position, on: :create

  def self.default_for(tenant:, business_type: nil)
    scope = tenant.lead_pipelines.active.ordered
    for_business_type(tenant: tenant, business_type: business_type) || scope.find_by(default_general: true) || scope.first
  end

  def self.for_business_type(tenant:, business_type:)
    attribute = case business_type.to_s
                when "sale", "venda", "sales" then :default_for_sale
                when "rental", "locacao", "locação", "rentals" then :default_for_rental
                when "daily", "diaria", "diária", "temporada" then :default_for_daily
                end
    scope = tenant.lead_pipelines.active.ordered
    return scope.find_by(attribute => true) if attribute
    scope.find_by(kind: "mixed") if %w[ambos mixed sale_rent].include?(business_type.to_s)
  end

  def self.ensure_default!(tenant:)
    existing = default_for(tenant:)
    return existing if existing

    Leads::OperationalPipelineTemplate.apply!(tenant: tenant)
  end

  def default_stage
    stages.active.ordered.first || stages.ordered.first
  end

  def closing_stages
    stages.where(tenant_id: tenant_id).active.where(stage_type: "won").ordered
  end

  def google_event_warning
    return unless stages.where.not(google_event: "none").group(:google_event).having("COUNT(*) > 1").exists?

    "Só o primeiro envio de cada lead conta para o Google."
  end

  private

  def assign_position
    return if position.present?

    self.position = (tenant.lead_pipelines.maximum(:position) || -1) + 1
  end

  def single_default_per_kind
    return if tenant_id.blank?

    {
      default_general: default_general?,
      default_for_sale: default_for_sale?,
      default_for_rental: default_for_rental?,
      default_for_daily: default_for_daily?
    }.each do |attribute, enabled|
      next unless enabled

      duplicate = tenant.lead_pipelines.where(attribute => true).where.not(id: id).exists?
      errors.add(attribute, "já existe para outro funil") if duplicate
    end
  end
end
