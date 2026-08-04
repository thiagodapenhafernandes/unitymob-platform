class PublicForm < ApplicationRecord
  include TenantScoped

  CATEGORIES = {
    "property_announcement" => "Anuncie seu imóvel",
    "partnership" => "Parcerias",
    "career" => "Trabalhe conosco",
    "landing_page" => "Landing page",
    "custom" => "Personalizado"
  }.freeze

  DEFAULT_ANNOUNCE_SLUG = "anuncie-seu-imovel".freeze
  DEFAULT_PARTNERSHIP_SLUG = "corretor-parceiro".freeze
  DEFAULT_WORK_WITH_US_SLUG = "trabalhe-conosco".freeze

  has_many :fields,
           -> { order(:position, :id) },
           class_name: "PublicFormField",
           dependent: :destroy,
           inverse_of: :public_form
  has_many :submissions, class_name: "PublicFormSubmission", dependent: :restrict_with_error

  accepts_nested_attributes_for :fields, allow_destroy: true, reject_if: :blank_field_attributes?

  validates :name, :slug, :category, :title, :submit_label, :success_message, presence: true
  validates :slug, uniqueness: { scope: :tenant_id }, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :category, inclusion: { in: CATEGORIES.keys }
  validates :redirect_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }

  before_validation :normalize_slug
  before_validation :normalize_modal_config

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(active: :desc, category: :asc, name: :asc) }

  def self.ensure_default_announce_property!(tenant:)
    form = tenant.public_forms.find_or_initialize_by(slug: DEFAULT_ANNOUNCE_SLUG)
    form.assign_attributes(default_announce_attributes) if form.new_record?
    form.save! if form.changed?
    form.ensure_default_announce_fields!
    form
  end

  def self.ensure_default_site_forms!(tenant:)
    [
      ensure_default_announce_property!(tenant: tenant),
      ensure_default_partnership!(tenant: tenant),
      ensure_default_work_with_us!(tenant: tenant)
    ]
  end

  def self.ensure_default_partnership!(tenant:)
    form = tenant.public_forms.find_or_initialize_by(slug: DEFAULT_PARTNERSHIP_SLUG)
    form.assign_attributes(default_partnership_attributes) if form.new_record?
    form.save! if form.changed?
    form.ensure_default_fields!(default_partnership_fields)
    form
  end

  def self.ensure_default_work_with_us!(tenant:)
    form = tenant.public_forms.find_or_initialize_by(slug: DEFAULT_WORK_WITH_US_SLUG)
    form.assign_attributes(default_work_with_us_attributes) if form.new_record?
    form.save! if form.changed?
    form.ensure_default_fields!(default_work_with_us_fields)
    form
  end

  def self.default_announce_attributes
    {
      name: "Anuncie seu imóvel",
      category: "property_announcement",
      title: "Vamos começar?",
      subtitle: "Preencha os dados abaixo e entraremos em contato.",
      submit_label: "Solicitar validação",
      success_message: "Recebemos seus dados. Nosso time entrará em contato.",
      active: true,
      modal_enabled: true,
      modal_config: {
        "eyebrow" => "Anuncie seu imóvel",
        "headline" => "Alcance compradores certos com a curadoria premium da Salute.",
        "benefits" => ["Visibilidade privilegiada", "Consultoria especializada", "Fotos profissionais"]
      }
    }
  end

  def self.default_partnership_attributes
    {
      name: "Corretor parceiro",
      category: "partnership",
      title: "Quero ser parceiro",
      subtitle: "Preencha os dados e nosso time entra em contato.",
      submit_label: "Enviar solicitação",
      success_message: "Solicitação enviada com sucesso. Nosso time de parcerias entrará em contato.",
      active: true,
      modal_enabled: true,
      modal_config: {
        "eyebrow" => "Parcerias",
        "headline" => "Potencialize seus negócios com uma curadoria de imóveis qualificados.",
        "benefits" => ["Portfólio premium", "Suporte especializado", "Parceria segura"]
      }
    }
  end

  def self.default_work_with_us_attributes
    {
      name: "Trabalhe conosco",
      category: "career",
      title: "Faça parte da equipe",
      subtitle: "Conte um pouco sobre sua experiência e entraremos em contato.",
      submit_label: "Enviar currículo",
      success_message: "Currículo enviado com sucesso. Entraremos em contato em breve.",
      active: true,
      modal_enabled: true,
      modal_config: {
        "eyebrow" => "Carreira",
        "headline" => "Faça parte de uma operação imobiliária focada em crescimento.",
        "benefits" => ["Crescimento profissional", "Equipe colaborativa", "Treinamento constante"]
      }
    }
  end

  def ensure_default_announce_fields!
    ensure_default_fields!(default_announce_fields)
  end

  def ensure_default_fields!(field_attributes)
    field_attributes.each do |attrs|
      fields.find_or_create_by!(name: attrs[:name]) { |field| field.assign_attributes(attrs) }
    end
  end

  def default_announce?
    slug == DEFAULT_ANNOUNCE_SLUG
  end

  def category_label
    CATEGORIES.fetch(category, category.to_s.humanize)
  end

  def to_param
    slug
  end

  def webhook_origin
    "public_form:#{slug}"
  end

  def blank_field_attributes?(attrs)
    attrs["label"].blank? && attrs["name"].blank? && attrs["field_type"].blank?
  end

  private

  def normalize_slug
    base = slug.presence || name
    self.slug = base.to_s.parameterize
  end

  def normalize_modal_config
    config = modal_config.to_h
    if config["benefits"].is_a?(String)
      config["benefits"] = config["benefits"].lines.map(&:strip).reject(&:blank?)
    end
    self.modal_config = config.compact
  end

  def default_announce_fields
    [
      { field_type: "text", name: "name", label: "Nome completo", placeholder: "Nome completo", required: true, position: 10 },
      { field_type: "email", name: "email", label: "Melhor e-mail", placeholder: "Melhor e-mail", required: false, position: 20 },
      { field_type: "tel", name: "phone", label: "WhatsApp / Telefone", placeholder: "WhatsApp / Telefone", required: true, position: 30 },
      { field_type: "select", name: "interest", label: "Interesse", placeholder: "Selecione", required: true, position: 40, options: [{ "label" => "Venda", "value" => "venda" }, { "label" => "Locação", "value" => "locacao" }] },
      { field_type: "text", name: "city_state", label: "Cidade / UF", placeholder: "Cidade / UF", required: true, position: 50 },
      { field_type: "text", name: "neighborhood_or_building", label: "Bairro ou edifício", placeholder: "Bairro ou edifício", required: false, position: 60 },
      { field_type: "textarea", name: "property_details", label: "Sobre o imóvel", placeholder: "Metragem, valor, estado do imóvel e observações", required: true, position: 70 }
    ]
  end

  def self.default_partnership_fields
    [
      { field_type: "text", name: "name", label: "Nome completo", required: true, position: 10 },
      { field_type: "email", name: "email", label: "E-mail", required: true, position: 20 },
      { field_type: "tel", name: "phone", label: "Telefone", required: true, position: 30 },
      { field_type: "text", name: "creci", label: "CRECI", required: false, position: 40 },
      { field_type: "text", name: "city", label: "Cidade", required: false, position: 50 },
      { field_type: "text", name: "state", label: "UF", required: false, position: 60 },
      { field_type: "textarea", name: "property_description", label: "Descrição do imóvel / demanda", required: true, position: 70 }
    ]
  end

  def self.default_work_with_us_fields
    [
      { field_type: "text", name: "name", label: "Nome completo", required: true, position: 10 },
      { field_type: "email", name: "email", label: "E-mail", required: true, position: 20 },
      { field_type: "tel", name: "phone", label: "Telefone", required: true, position: 30 },
      { field_type: "text", name: "creci", label: "CRECI", required: false, position: 40 },
      { field_type: "select", name: "experience", label: "Experiência", required: false, position: 50, options: [{ "label" => "Iniciante", "value" => "iniciante" }, { "label" => "1 a 3 anos", "value" => "1_3_anos" }, { "label" => "Mais de 3 anos", "value" => "mais_3_anos" }] },
      { field_type: "textarea", name: "message", label: "Mensagem", required: true, position: 60 }
    ]
  end
end
