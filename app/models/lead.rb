class Lead < ApplicationRecord
  include TenantScoped

  DEFAULT_STATUS = "Novo".freeze
  LEGACY_STATUSES = ["Novo", "Em Atendimento", "Aguardando Aceite", "Represado", "Descartado", "Concluido"].freeze
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

  belongs_to :admin_user, optional: true
  belongs_to :shared_by_admin_user, class_name: "AdminUser", optional: true
  belongs_to :distribution_rule, optional: true
  has_many :lead_audit_logs
  has_many :activities, class_name: "LeadActivity", dependent: :destroy
  has_many :secure_links, dependent: :destroy

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
  has_many :whatsapp_campaign_messages, dependent: :destroy
  has_many :tasks, dependent: :nullify
  has_many :appointments, dependent: :nullify
  has_many :proposals, dependent: :destroy
  has_many :lead_labelings, dependent: :destroy
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

  after_create :record_audit_create
  after_update :record_audit_update
  after_destroy :record_audit_destroy
  after_create_commit :route_lead
  after_create_commit :dispatch_automation_created
  after_update_commit :dispatch_automation_stage_changed

  before_validation :normalize_status
  before_validation :normalize_tags

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

  # Destinatário para a Cloud API: telefone se houver, senão BSUID.
  # (O link wa.me só existe com telefone; por BSUID, mensageia-se via API.)
  def whatsapp_recipient
    return display_phone if display_phone.present?
    return { user_id: business_scoped_user_id } if business_scoped_user_id.present?

    nil
  end

  def direct_whatsapp_url
    number = display_phone&.gsub(/\D/, '')
    return nil if number.blank?
    
    # Ensure 55 prefix if not present and sounds like BR
    number = "55#{number}" if number.length <= 11
    
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

  def self.status_options
    tenant = Current.tenant || raise(ArgumentError, "Tenant obrigatório para listar status de leads")
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

  def self.default_status(tenant: Current.tenant)
    status_options_for_tenant(tenant).first || DEFAULT_STATUS
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ArgumentError
    DEFAULT_STATUS
  end

  def self.status_options_for_tenant(tenant)
    raise ArgumentError, "Tenant obrigatório para listar status de leads" if tenant.blank?

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

  def normalize_status
    self.status = self.class.status_value(status)
  end

  def normalize_tags
    self.tags = self.class.normalize_tags_value(tags)
  end

  def associated_records_must_belong_to_tenant
    return if tenant_id.blank?

    {
      admin_user: admin_user,
      shared_by_admin_user: shared_by_admin_user,
      distribution_rule: distribution_rule
    }.each do |attribute, record|
      next if record.blank? || record.tenant_id == tenant_id

      errors.add(attribute, "deve pertencer ao mesmo Tenant")
    end

    if property_id.present? && !tenant.habitations.exists?(id: property_id)
      errors.add(:property_id, "deve pertencer ao mesmo Tenant")
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
