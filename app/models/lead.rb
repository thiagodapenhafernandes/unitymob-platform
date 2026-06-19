class Lead < ApplicationRecord
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
  has_many :seo_conversion_events, dependent: :nullify
  has_many :tasks, dependent: :nullify
  has_many :appointments, dependent: :nullify
  has_many :proposals, dependent: :destroy
  
  after_create :record_audit_create
  after_update :record_audit_update
  after_destroy :record_audit_destroy
  after_create_commit :route_lead
  after_create_commit :dispatch_automation_created
  after_update_commit :dispatch_automation_stage_changed

  before_validation :normalize_status

  scope :novo, -> { where(status: status_value(:novo)) }
  scope :em_atendimento, -> { where(status: status_value(:em_atendimento)) }
  scope :waiting_acceptance, -> { where(status: status_value(:waiting_acceptance)) }
  scope :represado, -> { where(status: status_value(:represado)) }
  scope :descartado, -> { where(status: status_value(:descartado)) }
  scope :concluido, -> { where(status: status_value(:concluido)) }
  scope :holding, -> { represado }
  scope :by_origin, ->(origin) { where(origin: origin) if origin.present? }

  validates :name, :phone, presence: true
  
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
    property = Habitation.find_by(id: property_id)
    fallback_message = if property
      "Olá, meu nome é #{display_name}. Estou interessado no imóvel #{property.codigo}. (Origem: #{origin})"
    else
      "Olá, meu nome é #{display_name}. Gostaria de mais informações. (Origem: #{origin})"
    end

    WhatsappBusinessIntegration.current.whatsapp_url_for(habitation: property, message: message.presence || fallback_message)
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

  def self.origin_options
    AttributeOption.where(context: "lead", category: "source").order(name: :asc).pluck(:name)
  end

  def self.status_options
    relation = AttributeOption.where(context: "lead", category: "status")
    relation = if AttributeOption.column_names.include?("position")
                 relation.order(Arel.sql("position ASC NULLS LAST")).order(name: :asc)
               else
                 relation.order(name: :asc)
               end
    catalog_statuses = relation.pluck(:name)
    return LEGACY_STATUSES if catalog_statuses.blank?

    catalog_statuses
  end

  def self.status_value(value)
    raw = value.to_s.strip
    return default_status if raw.blank?

    STATUS_ALIASES[raw] || STATUS_ALIASES[raw.downcase] || raw
  end

  def self.default_status
    status_options.first || DEFAULT_STATUS
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    DEFAULT_STATUS
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
    Leads::RoutingService.route!(self)
  end

  def dispatch_automation_created
    Automation::Dispatcher.dispatch(:lead_created, self)
  end

  def dispatch_automation_stage_changed
    return unless saved_change_to_status?
    Automation::Dispatcher.dispatch(:lead_stage_changed, self)
  end
end
