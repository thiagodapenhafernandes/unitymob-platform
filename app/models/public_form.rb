class PublicForm < ApplicationRecord
  include TenantScoped
  # Só "published" está no ar. Só "draft" salva sozinho no editor visual.
  include PublishableStatus

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

  MODAL_LAYOUTS = { "basic" => "Básico", "premium" => "Premium" }.freeze
  MODAL_SIZES = {
    "small" => "Pequeno",
    "default" => "Padrão",
    "large" => "Grande",
    "xl" => "Extra grande",
    "fullscreen" => "Tela cheia"
  }.freeze

  has_many :fields,
           -> { order(:position, :id) },
           class_name: "PublicFormField",
           dependent: :destroy,
           inverse_of: :public_form
  has_many :submissions, class_name: "PublicFormSubmission", dependent: :restrict_with_error
  belongs_to :distribution_rule, optional: true

  accepts_nested_attributes_for :fields, allow_destroy: true, reject_if: :blank_field_attributes?

  validates :name, :slug, :category, :title, :submit_label, :success_message, presence: true
  validates :webhook_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }
  validates :modal_layout, inclusion: { in: MODAL_LAYOUTS.keys }
  validates :modal_size, inclusion: { in: MODAL_SIZES.keys }
  validate :distribution_rule_belongs_to_tenant

  # Benefícios como [{ text:, icon: }]. Aceita o JSON do editor visual, o texto antigo (uma linha por benefício)
  # e listas já salvas (strings ou { "text", "icon" }).
  def benefit_items
    self.class.normalize_benefits(modal_config.to_h["benefits"]).map do |item|
      item.is_a?(Hash) ? { text: item["text"], icon: item["icon"] } : { text: item, icon: DEFAULT_BENEFIT_ICON }
    end
  end

  def benefits_json
    benefit_items.to_json
  end

  # Forma guardada: string quando usa o ícone padrão (compatível com os dados antigos); { "text", "icon" } nos demais.
  def self.normalize_benefits(raw)
    items = if raw.is_a?(String)
      parsed = begin
        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end
      parsed.is_a?(Array) ? parsed : raw.lines
    else
      Array(raw)
    end

    items.filter_map do |item|
      text, icon = item.is_a?(Hash) ? [item["text"] || item[:text], item["icon"] || item[:icon]] : [item, nil]
      text = text.to_s.strip
      next if text.blank?

      icon = icon.to_s
      icon.present? && icon != DEFAULT_BENEFIT_ICON && BENEFIT_ICONS.key?(icon) ? { "text" => text, "icon" => icon } : text
    end
  end

  def basic_layout?
    modal_layout == "basic"
  end
  validates :slug, uniqueness: { scope: :tenant_id }, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :category, inclusion: { in: CATEGORIES.keys }
  validate :redirect_url_is_internal_or_tenant_domain

  before_validation :normalize_slug
  before_validation :normalize_modal_config
  before_validation :sanitize_subtitle

  # Texto principal (subtitle) vem do Trix: HTML restrito ao que o editor gera.
  RICH_TEXT_TAGS = %w[strong b em i u del strike a br div p ul ol li blockquote h1 span].freeze
  RICH_TEXT_ATTRIBUTES = %w[href style].freeze

  # Cores do modal guardadas em modal_config: só #rrggbb (vão para CSS, nunca texto livre).
  HEX_COLOR = /\A#[0-9a-f]{6}\z/

  # Benefícios da lateral do modal: texto + ícone (Bootstrap Icons). Só estes ícones são aceitos (vão para a classe CSS).
  DEFAULT_BENEFIT_ICON = "bi-check-circle-fill".freeze
  BENEFIT_ICONS = {
    "bi-check-circle-fill" => "Check", "bi-star-fill" => "Estrela", "bi-shield-check" => "Segurança",
    "bi-lightning-charge-fill" => "Rapidez", "bi-heart-fill" => "Coração", "bi-graph-up-arrow" => "Crescimento",
    "bi-people-fill" => "Equipe", "bi-clock-fill" => "Tempo", "bi-award-fill" => "Prêmio",
    "bi-house-heart-fill" => "Imóvel", "bi-geo-alt-fill" => "Local", "bi-telephone-fill" => "Telefone",
    "bi-camera-fill" => "Fotos", "bi-cash-coin" => "Valor", "bi-key-fill" => "Chaves", "bi-patch-check-fill" => "Selo"
  }.freeze
  MODAL_COLOR_KEYS = %w[aside_bg aside_fg aside_accent body_bg submit_bg submit_fg].freeze

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(active: :desc, category: :asc, name: :asc) }

  SAMPLE_FIELDS = [
    { field_type: "text", name: "name", label: "Nome completo", placeholder: "Seu nome", required: true, position: 10 },
    { field_type: "email", name: "email", label: "E-mail", placeholder: "voce@exemplo.com", required: false, position: 20 },
    { field_type: "tel", name: "phone", label: "WhatsApp / Telefone", placeholder: "(00) 00000-0000", required: true, position: 30 },
    { field_type: "textarea", name: "message", label: "Mensagem", placeholder: "Como podemos ajudar?", required: false, position: 40 }
  ].freeze

  # Formulário novo do admin: rascunho já com conteúdo de exemplo. Os textos da lateral dizem o nome
  # do próprio elemento, para quem abre o editor saber onde cada parte aparece no modal.
  def self.build_sample(tenant:)
    base = "Novo formulário"
    name = base
    counter = 1
    name = "#{base} #{counter += 1}" while tenant.public_forms.exists?(slug: name.parameterize)

    form = tenant.public_forms.new(
      name: name,
      slug: name.parameterize,
      status: "draft",
      modal_enabled: true,
      title: "Título do formulário",
      subtitle: "Texto principal: explique em poucas linhas o que acontece depois do envio.",
      submit_label: "Enviar",
      success_message: "Mensagem enviada com sucesso.",
      modal_config: {
        "eyebrow" => "Chamada",
        "headline" => "Título da lateral",
        "benefits" => ["Benefício 1", "Benefício 2", "Benefício 3"]
      }
    )
    SAMPLE_FIELDS.each { |attrs| form.fields.build(attrs) }
    form
  end

  # Quando um destino `#modal-ID` não abre nada no site, o motivo em português (nil se está tudo certo ou se
  # o destino não é um modal). O modal só existe no site com o formulário Publicado e "Disponível para modal".
  def self.modal_link_problem(tenant:, url:)
    slug = url.to_s.strip[/\A#modal-([a-z0-9-]+)\z/i, 1]
    return unless slug

    form = tenant.public_forms.find_by(slug: slug.downcase)
    return "Nenhum formulário tem o ID “#{slug}”. Confira o ID na tela de Formulários." unless form
    return "O formulário “#{form.name}” está em #{form.status_label}: publique para o modal abrir no site." unless form.published?

    "O formulário “#{form.name}” está com “Disponível para modal” desligado (bloco Publicação)." unless form.modal_enabled?
  end

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
        "headline" => "Alcance compradores certos com uma curadoria imobiliária especializada.",
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

  def routes_to_distribution?
    distribution_rule_id.present?
  end

  private

  def distribution_rule_belongs_to_tenant
    return if distribution_rule.blank?
    return if distribution_rule.tenant_id == tenant_id

    errors.add(:distribution_rule, "deve ser da mesma conta")
  end

  def redirect_url_is_internal_or_tenant_domain
    return if redirect_url.blank?

    uri = URI.parse(redirect_url.to_s)
    return if uri.relative? && redirect_url.start_with?("/") && !redirect_url.start_with?("//")
    return if uri.is_a?(URI::HTTP) && tenant_redirect_host?(uri.host)

    errors.add(:redirect_url, "deve ser um caminho interno ou uma URL de domínio da conta")
  rescue URI::InvalidURIError
    errors.add(:redirect_url, "deve ser um caminho interno ou uma URL de domínio da conta")
  end

  def tenant_redirect_host?(host)
    normalized_host = TenantDomain.normalize_host(host)
    return false if normalized_host.blank? || tenant.blank?

    comparable_host = normalized_host.delete_prefix("www.")
    tenant.tenant_domains.active.pluck(:hostname).any? do |hostname|
      TenantDomain.normalize_host(hostname).delete_prefix("www.") == comparable_host
    end
  end

  def normalize_slug
    base = slug.presence || name
    self.slug = base.to_s.parameterize
  end

  def sanitize_subtitle
    return if subtitle.blank?

    helpers = ActionController::Base.helpers
    self.subtitle = helpers.strip_tags(subtitle).squish.blank? ? nil : helpers.sanitize(subtitle, tags: RICH_TEXT_TAGS, attributes: RICH_TEXT_ATTRIBUTES)
  end

  def normalize_modal_config
    config = modal_config.to_h
    config["benefits"] = self.class.normalize_benefits(config["benefits"]) if config.key?("benefits")
    MODAL_COLOR_KEYS.each do |key|
      color = config[key].to_s.strip.downcase
      config[key] = color.match?(HEX_COLOR) ? color : nil
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
