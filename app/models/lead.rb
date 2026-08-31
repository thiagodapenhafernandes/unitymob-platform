class Lead < ApplicationRecord
  include TenantScoped
  include PhoneNormalizable

  DEFAULT_STATUS = "Novo".freeze
  LEGACY_STATUSES = ["Novo", "Em Atendimento", "Aguardando Aceite", "Represado", "Descartado", "Concluido"].freeze
  NON_OPERATIONAL_STATUS_FALLBACKS = [
    "Descartado",
    "Concluido",
    "Finalizado",
    "Negócio fechado",
    "Negocio fechado",
    "Vendido",
    "Locado",
    "Ganho",
    "Perdido",
    "Sem interesse",
    "Arquivado"
  ].freeze
  STATUS_ALIASES = {
    "novo" => "Novo",
    "em_atendimento" => "Em Atendimento",
    "waiting_acceptance" => "Aguardando Aceite",
    "aguardando_aceite" => "Aguardando Aceite",
    "represado" => "Represado",
    "descartado" => "Descartado",
    "concluido" => "Concluido",
    "received" => "Novo"
  }.freeze
  QUALIFICATION_STATUSES = LeadPipelineStagePolicy::QUALIFICATION_OPTIONS.freeze

  belongs_to :admin_user, optional: true
  belongs_to :shared_by_admin_user, class_name: "AdminUser", optional: true
  belongs_to :distribution_rule, optional: true
  belongs_to :external_lead_integration, optional: true
  belongs_to :lead_pipeline, optional: true
  belongs_to :lead_pipeline_stage, optional: true
  belongs_to :archive_reason, class_name: "AttributeOption", optional: true
  belongs_to :archived_by_admin_user, class_name: "AdminUser", optional: true
  has_many :lead_audit_logs
  has_many :activities, class_name: "LeadActivity", dependent: :destroy
  has_many :stage_automation_executions,
           class_name: "LeadPipelineStageAutomationExecution",
           dependent: :destroy
  has_many :secure_links, dependent: :destroy
  has_many :ai_property_share_collections, dependent: :nullify

  # Reivindicação atômica (Shark Tank): o 1º corretor a aceitar vira dono.
  # Retorna true se ESTE corretor pegou o lead; false se já estava com alguém.
  def self.claim!(lead_id, corretor_id)
    return false if corretor_id.blank?

    where(id: lead_id, admin_user_id: nil, status: status_value(:waiting_acceptance))
      .update_all(admin_user_id: corretor_id, status: status_value(:em_atendimento), updated_at: Time.current) == 1
  end
  has_many :public_navigation_sessions, dependent: :nullify
  has_many :public_navigation_events, dependent: :nullify
  has_many :client_property_interests, foreign_key: :lead_id, dependent: :nullify
  has_many :automation_events, dependent: :nullify
  has_many :seo_conversion_events, dependent: :nullify
  has_many :push_delivery_events, dependent: :nullify
  has_many :whatsapp_campaign_messages, dependent: :destroy
  has_many :tasks, dependent: :nullify
  has_many :appointments, dependent: :nullify
  has_many :proposals, dependent: :destroy
  has_many :lead_labelings, dependent: :destroy
  has_many :lead_favorites, dependent: :destroy
  has_many :property_interests, class_name: "LeadPropertyInterest", dependent: :destroy
  has_many :interest_properties, through: :property_interests, source: :habitation
  has_many :lead_labels, through: :lead_labelings

  # Etiquetas são privadas por corretor: só retorna as marcações cujo label
  # pertence ao usuário informado.
  def labels_for(admin_user)
    return LeadLabel.none if admin_user.blank?

    lead_labels.for_user(admin_user).ordered
  end

  # Versão em memória para listas/kanban: usa a associação já pré-carregada
  # (includes) e evita N+1. Retorna um Array de LeadLabel do usuário.
  def preloaded_labels_for(admin_user)
    return [] if admin_user.blank?

    labels = if association(:lead_labelings).loaded?
      lead_labelings.filter_map { |labeling| labeling.lead_label if labeling.lead_label&.admin_user_id == admin_user.id }
    else
      lead_labels.for_user(admin_user)
    end

    labels.sort_by { |label| [label.position, label.name] }
  end

  def shared_property_ids
    collection_ids = ai_property_share_collections
      .joins(:items)
      .distinct
      .pluck("ai_property_share_items.habitation_id")

    activity_ids = activities
      .where(kind: "property_share")
      .pluck(:metadata)
      .flat_map { |metadata| Array(metadata&.dig("habitation_ids")) }

    (collection_ids + activity_ids).map(&:to_i).reject(&:zero?).uniq
  end

  def shared_property_statuses
    statuses = shared_property_ids.index_with { "sent" }

    ai_property_share_collections.includes(:audit_events, :habitations).find_each do |collection|
      collection_property_ids = collection.habitations.map(&:id)

      collection.audit_events.each do |event|
        status = property_share_event_status(event.event_type)
        next if status.blank?

        property_ids = event.habitation_id.present? ? [event.habitation_id] : collection_property_ids
        property_ids.each do |property_id|
          property_id = property_id.to_i
          next if property_id.zero?

          statuses[property_id] = stronger_property_share_status(statuses[property_id], status)
        end
      end
    end

    statuses
  end

  after_create :record_audit_create
  after_update :record_audit_update
  after_destroy :record_audit_destroy
  after_create_commit :route_lead, unless: :skip_automatic_routing?
  after_create_commit :dispatch_automation_created, unless: :skip_automatic_routing?
  after_update_commit :dispatch_automation_stage_changed, unless: :skip_automatic_routing?

  before_validation :normalize_status
  before_validation :sync_pipeline_stage
  before_validation :normalize_tags
  before_save :sync_closed_at
  normalize_phone_fields :phone, :client_phone, :agent_phone

  scope :novo, -> { where(status: status_value(:novo)) }
  scope :em_atendimento, -> { where(status: status_value(:em_atendimento)) }
  scope :waiting_acceptance, -> { where(status: status_value(:waiting_acceptance)) }
  scope :represado, -> { where(status: status_value(:represado)) }
  scope :descartado, -> { where(status: status_value(:descartado)) }
  scope :concluido, -> { where(status: status_value(:concluido)) }
  scope :holding, -> { represado }
  scope :by_origin, ->(origin) { where(origin: origin) if origin.present? }
  scope :with_any_tags, ->(values) {
    normalized = normalize_tags_value(values)
    if normalized.present?
      conditions = normalized.map { "leads.tags @> ?" }.join(" OR ")
      where(conditions, *normalized.map { |tag| [tag].to_json })
    else
      all
    end
  }
  scope :without_any_tags, ->(values) {
    normalized = normalize_tags_value(values)
    if normalized.present?
      conditions = normalized.map { "leads.tags @> ?" }.join(" OR ")
      where.not(conditions, *normalized.map { |tag| [tag].to_json })
    else
      all
    end
  }

  validates :name, presence: true
  # Telefone é obrigatório, exceto quando o lead é identificado por BSUID
  # (usuário do WhatsApp que esconde o número — recurso de username da Meta).
  validates :phone, presence: true, unless: -> { business_scoped_user_id.present? }
  validate :associated_records_must_belong_to_tenant

  # Motivo e justificativa só são exigidos no fluxo dedicado de arquivar
  # (Admin::LeadsController#archive) — o update genérico (funil/kanban) segue
  # sem essa exigência.
  attr_writer :archiving

  def archiving?
    @archiving == true
  end

  validates :archive_reason_id, presence: { message: "é obrigatório para arquivar o lead" }, if: :archiving?
  validates :archive_note, presence: { message: "é obrigatória para arquivar o lead" }, if: :archiving?
  validates :broker_qualification_status,
            :manager_qualification_status,
            inclusion: { in: QUALIFICATION_STATUSES.keys },
            allow_blank: true

  attr_writer :skip_automatic_routing

  def skip_automatic_routing?
    @skip_automatic_routing == true
  end
  
  def display_name
    client_name.presence || name
  end

  def display_email
    client_email.presence || email
  end

  def display_phone
    client_phone.presence || phone
  end

  def whatsapp_url(message: nil)
    property = tenant.habitations.find_by(id: property_id)
    fallback_message = if property
      "Olá, meu nome é #{display_name}. Estou interessado no imóvel #{property.codigo}. (Origem: #{origin})"
    else
      "Olá, meu nome é #{display_name}. Gostaria de mais informações. (Origem: #{origin})"
    end

    WhatsappBusinessIntegration.current(tenant).whatsapp_url_for(habitation: property, message: message.presence || fallback_message)
  end

  # Destinatário para a Cloud API: BSUID primeiro; telefone fica como fallback.
  # (O link wa.me só existe com telefone; por BSUID, mensageia-se via API.)
  def whatsapp_recipient
    return { user_id: business_scoped_user_id } if business_scoped_user_id.present?
    return display_phone if display_phone.present?

    nil
  end

  def direct_whatsapp_url
    number = Phones::Normalizer.call(display_phone)
    return nil if number.blank?

    "https://wa.me/#{number}"
  end

  def answer_for(key)
    return nil unless custom_answers.is_a?(Array)
    found = custom_answers.find { |item| item["key"].to_s == key.to_s }
    found ? found["answer"] : nil
  end

  def tag_list
    self.class.normalize_tags_value(tags)
  end

  def business_label
    info = other_information.is_a?(Hash) ? other_information : {}
    attribution = attribution_data.is_a?(Hash) ? attribution_data : {}
    external_payload = info["external_lead_payload"].is_a?(Hash) ? info["external_lead_payload"] : {}
    external_attributes = external_payload["attributes"].is_a?(Hash) ? external_payload["attributes"] : {}
    product_data = attribution["product"].is_a?(Hash) ? attribution["product"] : external_attributes["product"].to_h

    text = [
      lead_type,
      product,
      notes,
      status,
      product_data["description"],
      product_data["negotiation_name"],
      product_data.dig("real_estate_detail", "negotiation_name"),
      external_attributes["description"],
      external_attributes.dig("funnel_status", "name"),
      external_attributes.dig("lead_status", "name")
    ].compact.join(" ").parameterize(separator: "_")

    return "Captação" if text.match?(/captacao|captar|proprietario|proprietaria/)
    return "Locação" if text.match?(/locacao|aluguel|alugar|rental|locar/)
    return "Venda" if text.match?(/venda|comprar|compra|sale|vend/)

    nil
  end

  def qualification_status_for(admin_user)
    qualification_field_for(admin_user) == :broker_qualification_status ? broker_qualification_status : manager_qualification_status
  end

  def qualification_field_for(admin_user)
    LeadPipelineStagePolicy.role_for(admin_user) == "broker" ? :broker_qualification_status : :manager_qualification_status
  end

  def qualification_label_for(admin_user)
    QUALIFICATION_STATUSES[qualification_status_for(admin_user).to_s]
  end

  def qualification_divergent?
    broker_qualification_status.present? &&
      manager_qualification_status.present? &&
      broker_qualification_status != manager_qualification_status
  end

  def self.origin_options(scope: all, tenant: Current.tenant)
    raise ArgumentError, "Tenant obrigatório para listar origens de leads" if tenant.blank?

    catalog_options = tenant.attribute_options.where(context: "lead", category: "source").order(name: :asc).pluck(:name)
    recorded_origins = scope.where.not(origin: [nil, ""])
      .distinct
      .pluck(:origin)

    (catalog_options + recorded_origins)
      .map { |origin| origin.to_s.strip }
      .reject(&:blank?)
      .uniq
      .sort_by(&:downcase)
  end

  def self.tag_options(scope: all)
    # Agrega no banco (DISTINCT dos elementos do jsonb) em vez de puxar o array
    # de tags de todos os leads pro Ruby: transfere só o conjunto distinto.
    # A normalização Ruby roda apenas sobre esse conjunto pequeno, preservando
    # o tratamento de dados legados (aspas, JSON aninhado, split por ;/,).
    scope.reorder(nil)
      .where("jsonb_typeof(leads.tags) = 'array'")
      .where("leads.tags <> '[]'::jsonb")
      .pluck(Arel.sql("DISTINCT jsonb_array_elements_text(leads.tags)"))
      .flat_map { |value| normalize_tags_value(value) }
      .uniq
      .sort_by(&:downcase)
  end

  def self.normalize_tags_value(value)
    case value
    when Array
      value.flat_map { |item| normalize_tags_value(item) }
    when Hash
      value.values.flat_map { |item| normalize_tags_value(item) }
    else
      raw = value.to_s.strip
      return [] if raw.blank?

      parsed = parsed_tags_from(raw)
      parsed.is_a?(Hash) ? parsed.values : parsed
    end
      .map { |tag| tag.to_s.strip.gsub(/["']/, "") }
      .reject(&:blank?)
      .uniq
  end

  def self.parsed_tags_from(raw)
    if raw.start_with?("[", "{")
      begin
        return JSON.parse(raw)
      rescue JSON::ParserError
        begin
          return JSON.parse(raw.tr("'", '"'))
        rescue JSON::ParserError
          # Falls through to tolerant parsing below.
        end
      end
    end

    raw.tr("[]{}", "")
       .split(/[;,]/)
       .map { |part| part.to_s.strip.gsub(/["']/, "") }
  end

  def self.status_options(pipeline: nil, tenant: Current.tenant)
    tenant ||= Current.tenant
    raise ArgumentError, "Tenant obrigatório para listar status de leads" if tenant.blank?

    tenant = pipeline.tenant if pipeline.present?
    if pipeline.present? || tenant.lead_pipelines.exists?
      target_pipeline = pipeline || LeadPipeline.default_for(tenant:)
      stages = target_pipeline&.stages&.active&.ordered&.pluck(:name)
      return stages if stages.present?
    end

    relation = tenant.attribute_options.where(context: "lead", category: "status")
    relation = if AttributeOption.column_names.include?("position")
                 relation.order(Arel.sql("position ASC NULLS LAST")).order(name: :asc)
               else
                 relation.order(name: :asc)
               end
    catalog_statuses = relation.pluck(:name)
    return LEGACY_STATUSES if catalog_statuses.blank?

    catalog_statuses
  end

  def self.status_value(value, tenant: Current.tenant)
    raw = value.to_s.strip
    return default_status(tenant: tenant) if raw.blank?

    STATUS_ALIASES[raw] || STATUS_ALIASES[raw.downcase] || raw
  end

  def self.non_operational_status_values(tenant: Current.tenant)
    pipeline_statuses = tenant&.lead_pipeline_stages&.where(stage_type: %w[won lost archived])&.pluck(:name)

    (NON_OPERATIONAL_STATUS_FALLBACKS + Array(pipeline_statuses))
      .map { |status| status_value(status, tenant:) }
      .compact_blank
      .uniq
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    NON_OPERATIONAL_STATUS_FALLBACKS
  end

  def self.default_status(tenant: Current.tenant, pipeline: nil)
    target_pipeline = pipeline || (LeadPipeline.default_for(tenant:) if tenant&.respond_to?(:lead_pipelines))
    stage_name = target_pipeline&.default_stage&.name
    return stage_name if stage_name.present?

    status_options_for_tenant(tenant).first || DEFAULT_STATUS
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ArgumentError
    DEFAULT_STATUS
  end

  def self.status_options_for_tenant(tenant, pipeline: nil)
    raise ArgumentError, "Tenant obrigatório para listar status de leads" if tenant.blank?

    target_pipeline = pipeline || LeadPipeline.default_for(tenant:)
    stages = target_pipeline&.stages&.active&.ordered&.pluck(:name)
    return stages if stages.present?

    relation = tenant.attribute_options.where(context: "lead", category: "status")
    relation = if AttributeOption.column_names.include?("position")
                 relation.order(Arel.sql("position ASC NULLS LAST")).order(name: :asc)
               else
                 relation.order(name: :asc)
               end
    catalog_statuses = relation.pluck(:name)
    return LEGACY_STATUSES if catalog_statuses.blank?

    catalog_statuses
  end

  def self.status_badge_class(status)
    case status_value(status)
    when "Novo" then "info"
    when "Em Atendimento" then "primary"
    when "Aguardando Aceite" then "warning"
    when "Represado" then "secondary"
    when "Descartado" then "danger"
    when "Concluido" then "success"
    else "dark"
    end
  end

  private

  def property_share_event_status(event_type)
    case event_type.to_s
    when "collection_opened"
      "viewed"
    when "property_opened"
      "opened"
    when "interest_created", "interest_repeated"
      "interested"
    end
  end

  def stronger_property_share_status(current, candidate)
    order = { "sent" => 0, "viewed" => 1, "opened" => 2, "interested" => 3 }
    order.fetch(candidate, 0) > order.fetch(current, 0) ? candidate : current
  end

  def normalize_status
    self.status = self.class.status_value(status)
  end

  def sync_pipeline_stage
    return if tenant.blank?

    self.lead_pipeline ||= lead_pipeline_stage&.lead_pipeline
    self.lead_pipeline ||= LeadPipeline.default_for(tenant:)

    if status.present? && (lead_pipeline_stage.blank? || status.to_s != lead_pipeline_stage.name.to_s || will_save_change_to_lead_pipeline_id?)
      matched_stage = LeadPipelineStage.matching_name(tenant: tenant, pipeline: lead_pipeline, name: status)
      self.lead_pipeline_stage = matched_stage if matched_stage
    end

    if status.present? && lead_pipeline_stage.present? && status.to_s != lead_pipeline_stage.name.to_s
      self.lead_pipeline_stage = nil
    end

    if lead_pipeline_stage.present?
      self.lead_pipeline = lead_pipeline_stage.lead_pipeline
      self.status = lead_pipeline_stage.name
      return
    end

    stage = LeadPipelineStage.matching_name(tenant: tenant, pipeline: lead_pipeline, name: status)
    stage ||= lead_pipeline&.default_stage if status.blank?
    if stage.present?
      self.lead_pipeline_stage = stage
      self.status = stage.name
    end
  end

  def normalize_tags
    self.tags = self.class.normalize_tags_value(tags)
  end

  def sync_closed_at
    if closed_status?
      self.closed_at ||= Time.current
    elsif will_save_change_to_status?
      self.closed_at = nil
    end
  end

  def closed_status?
    return true if self.class.status_value(status) == self.class.status_value(:concluido)
    return true if lead_pipeline_stage&.stage_type == "won"

    tenant&.lead_pipeline_stages&.active&.where(name: status, stage_type: "won")&.exists? || false
  end

  def associated_records_must_belong_to_tenant
    return if tenant_id.blank?

    {
      admin_user: admin_user,
      shared_by_admin_user: shared_by_admin_user,
      distribution_rule: distribution_rule,
      lead_pipeline: lead_pipeline,
      lead_pipeline_stage: lead_pipeline_stage
    }.each do |attribute, record|
      next if record.blank? || record.tenant_id == tenant_id

      errors.add(attribute, "deve pertencer ao mesmo Tenant")
    end

    if property_id.present? && !tenant.habitations.exists?(id: property_id)
      errors.add(:property_id, "deve pertencer ao mesmo Tenant")
    end

    if lead_pipeline_stage.present? && lead_pipeline.present? && lead_pipeline_stage.lead_pipeline_id != lead_pipeline_id
      errors.add(:lead_pipeline_stage, "deve pertencer ao funil do lead")
    end
  end

  def record_audit_create
    Leads::AuditChangeRecorder.record_create!(self)
  end

  def record_audit_update
    Leads::AuditChangeRecorder.record_update!(self)
  end

  def record_audit_destroy
    Leads::AuditChangeRecorder.record_destroy!(self)
  end

  def route_lead
    return unless persisted? && !destroyed?

    Leads::RoutingService.route!(self)
  end

  def dispatch_automation_created
    Automation::Dispatcher.dispatch(
      :lead_created,
      self,
      source: "lead",
      idempotency_key: "lead_created:#{id}"
    )
  end

  def dispatch_automation_stage_changed
    return unless saved_change_to_status?

    Automation::Dispatcher.dispatch(
      :lead_stage_changed,
      self,
      source: "lead",
      payload: {
        from: saved_change_to_status.first,
        to: saved_change_to_status.last
      }
    )
  end
end
