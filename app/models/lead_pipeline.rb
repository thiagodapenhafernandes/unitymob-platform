class LeadPipeline < ApplicationRecord
  include TenantScoped

  KINDS = {
    "sale" => "Venda",
    "rental" => "Locação",
    "mixed" => "Venda e locação",
    "custom" => "Personalizado"
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
    case business_type.to_s
    when "sale", "venda", "sales"
      scope.find_by(default_for_sale: true) || scope.find_by(default_general: true) || scope.first
    when "rental", "locacao", "locação", "rentals"
      scope.find_by(default_for_rental: true) || scope.find_by(default_general: true) || scope.first
    else
      scope.find_by(default_general: true) || scope.first
    end
  end

  def self.ensure_default!(tenant:)
    existing = default_for(tenant:)
    return existing if existing

    pipeline = tenant.lead_pipelines.create!(
      name: "Principal",
      kind: "mixed",
      default_general: true,
      default_for_sale: true,
      default_for_rental: true,
      position: 0
    )
    created_stages = DEFAULT_STAGE_DEFINITIONS.each_with_index.map do |definition, index|
      tenant.lead_pipeline_stages.create!(
        lead_pipeline: pipeline,
        name: definition.fetch(:name),
        stage_type: definition.fetch(:stage_type),
        color: definition.fetch(:color),
        position: index
      )
    end
    created_stages.each { |stage| stage.create_policy!(LeadPipelineStagePolicy.default_attributes.merge(tenant: tenant)) }
    created_stages.each_cons(2).with_index do |(stage, next_stage), index|
      tenant.lead_pipeline_stage_transitions.create!(
        lead_pipeline_stage: stage,
        next_stage: next_stage,
        position: index
      )
    end
    pipeline
  end

  def default_stage
    stages.active.ordered.first || stages.ordered.first
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
      default_for_rental: default_for_rental?
    }.each do |attribute, enabled|
      next unless enabled

      duplicate = tenant.lead_pipelines.where(attribute => true).where.not(id: id).exists?
      errors.add(attribute, "já existe para outro funil") if duplicate
    end
  end
end
