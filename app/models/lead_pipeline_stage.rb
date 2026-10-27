class LeadPipelineStage < ApplicationRecord
  include TenantScoped

  STAGE_TYPES = {
    "open" => "Aberta",
    "won" => "Ganha",
    "lost" => "Perdida",
    "archived" => "Arquivada"
  }.freeze
  # Evento Meta (Conversions API), condicionado ao momento configurado na etapa.
  # Eventos padrão: https://developers.facebook.com/docs/meta-pixel/reference/
  # QualifiedLead preserva o evento CRM já usado pela integração.
  META_CONVERSION_EVENTS = {
    "QualifiedLead" => "Lead qualificado",
    "Lead" => "Lead",
    "Contact" => "Contato",
    "Schedule" => "Agendamento",
    "SubmitApplication" => "Envio de inscrição ou solicitação",
    "CompleteRegistration" => "Cadastro concluído",
    "Purchase" => "Venda",
    "StartTrial" => "Início de período de teste",
    "Subscribe" => "Assinatura",
    "ViewContent" => "Visualização de conteúdo",
    "Search" => "Pesquisa",
    "FindLocation" => "Busca de localização",
    "CustomizeProduct" => "Personalização de produto",
    "AddToWishlist" => "Adição à lista de desejos",
    "AddToCart" => "Adição ao carrinho",
    "InitiateCheckout" => "Início de checkout",
    "AddPaymentInfo" => "Adição de informações de pagamento",
    "Donate" => "Doação",
    "PageView" => "Visualização de página"
  }.freeze
  GOOGLE_EVENTS = { "none" => "Nenhum", "qualify_lead" => "Lead qualificado", "visit" => "Visita realizada", "proposal" => "Proposta enviada", "closed" => "Fechamento" }.freeze
  validates :google_event, inclusion: { in: GOOGLE_EVENTS.keys }
  CONVERSION_TRIGGERS = {
    "stage_entered" => "Ao entrar na etapa", "qualified" => "Ao marcar como qualificado",
    "visit_completed" => "Ao concluir uma visita", "proposal_sent" => "Ao enviar uma proposta",
    "deal_closed" => "Ao concluir o negócio"
  }.freeze
  GOOGLE_ACTIONS = { "qualify_lead" => "qualified", "visit" => "visit_completed", "proposal" => "proposal_sent", "closed" => "deal_closed" }.freeze
  validates :google_event_trigger, :meta_event_trigger, inclusion: { in: CONVERSION_TRIGGERS.keys }
  validate :google_action_matches_event

  HEX_COLOR = /\A#\h{6}\z/
  DEFAULT_COLORS = %w[#2f80a0 #365f8f #8a63d2 #d97706 #08875d #e0402f #667085].freeze

  belongs_to :lead_pipeline
  has_many :leads, dependent: :nullify
  has_many :automations,
           class_name: "LeadPipelineStageAutomation",
           dependent: :destroy,
           inverse_of: :lead_pipeline_stage
  has_one :policy,
          class_name: "LeadPipelineStagePolicy",
          dependent: :destroy,
          inverse_of: :lead_pipeline_stage
  has_many :transitions,
           class_name: "LeadPipelineStageTransition",
           dependent: :destroy,
           inverse_of: :lead_pipeline_stage
  has_many :incoming_transitions,
           class_name: "LeadPipelineStageTransition",
           foreign_key: :next_stage_id,
           dependent: :destroy,
           inverse_of: :next_stage
  has_many :automation_executions,
           class_name: "LeadPipelineStageAutomationExecution",
           dependent: :destroy,
           inverse_of: :lead_pipeline_stage
  has_many :next_stages,
           through: :transitions,
           source: :next_stage

  validates :name, presence: true, uniqueness: { scope: [:tenant_id, :lead_pipeline_id], case_sensitive: false }
  validates :stage_type, inclusion: { in: STAGE_TYPES.keys }
  validates :meta_conversion_event, inclusion: { in: META_CONVERSION_EVENTS.keys }, allow_blank: true
  validates :color, format: { with: HEX_COLOR, message: "inválida" }, allow_blank: true
  validate :pipeline_must_belong_to_tenant

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(Arel.sql("position ASC NULLS LAST"), :name) }

  before_validation :assign_position, on: :create
  before_validation :infer_stage_type
  after_update_commit :sync_leads_status_on_rename, if: :saved_change_to_name?

  def policy_or_default
    policy || build_policy(LeadPipelineStagePolicy.default_attributes.merge(tenant: tenant))
  end

  def visible_to_admin_user?(admin_user)
    policy_or_default.visible_to_admin_user?(admin_user)
  end

  def summary_parts
    stage_policy = policy_or_default
    parts = []
    parts << "Visível para #{stage_policy.visible_role_labels.to_sentence}" if stage_policy.visible_role_labels.any?
    parts << "#{transitions.size} próxima(s) etapa(s)" if transitions.loaded? ? transitions.any? : transitions.exists?
    archive_automation = automations.active.where(action_type: "archive_lead").ordered.first
    parts << "Arquiva em #{archive_automation.after_amount} #{LeadPipelineStageAutomation::UNITS[archive_automation.after_unit]}" if archive_automation
    parts
  end

  def display_color
    return color if color.to_s.match?(HEX_COLOR)

    DEFAULT_COLORS[position.to_i % DEFAULT_COLORS.size]
  end

  def self.matching_name(tenant:, pipeline:, name:)
    return nil if tenant.blank? || pipeline.blank? || name.blank?

    normalized = normalized_name_key(name)
    where(tenant: tenant, lead_pipeline: pipeline).detect do |stage|
      normalized_name_key(stage.name) == normalized
    end
  end

  def self.sanitize_name(value)
    value.to_s.tr("_", " ").squish.sub(/[[:space:]]*[\.,;:!?]+[[:space:]]*\z/, "")
  end

  def self.normalized_name_key(value)
    I18n.transliterate(sanitize_name(value)).downcase.parameterize(separator: "_")
  end

  private

  def google_action_matches_event
    return if google_event == "none" || google_event_trigger == "stage_entered"
    return if GOOGLE_ACTIONS[google_event] == google_event_trigger

    errors.add(:google_event_trigger, "não corresponde ao evento Google selecionado")
  end

  def assign_position
    return if position.present? || lead_pipeline.blank?

    self.position = (lead_pipeline.stages.maximum(:position) || -1) + 1
  end

  def infer_stage_type
    self.name = self.class.sanitize_name(name)
    return if stage_type.present? && will_save_change_to_stage_type?

    self.stage_type = inferred_stage_type if stage_type.blank? || will_save_change_to_name?
  end

  def inferred_stage_type
    key = self.class.normalized_name_key(name)
    return "won" if key.match?(/concluido|vendido|locado|fechado|ganho/)
    return "lost" if key.match?(/descartado|perdido|sem_interesse/)
    return "archived" if key.match?(/arquivado/)

    stage_type.presence || "open"
  end

  def pipeline_must_belong_to_tenant
    return if tenant.blank? || lead_pipeline.blank? || lead_pipeline.tenant_id == tenant_id

    errors.add(:lead_pipeline, "deve pertencer ao mesmo Tenant")
  end

  def sync_leads_status_on_rename
    leads.update_all(status: name, updated_at: Time.current)
  end
end
