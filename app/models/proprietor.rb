class Proprietor < ApplicationRecord
  include TenantScoped
  include PhoneNormalizable

  CAPTURE_VEHICLES = [
    "Cliente indicado por outro cliente",
    "Active Campaign",
    "Amigo",
    "Anúncio jornal",
    "API",
    "Busca Paga | Facebook Ads",
    "Busca Paga | Google",
    "C2Sbot",
    "Casa Mineira",
    "Chat",
    "Chaves na Mão",
    "Cliente de Carteira",
    "Desconhecido",
    "Email",
    "Facebook - CTWA",
    "Facebook Ads",
    "Google",
    "Google - Locação",
    "Google - Venda",
    "Google Ads"
  ].freeze

  ISSUING_AUTHORITIES = [
    "SSP",
    "SSP/SC",
    "SSP SC",
    "SSP/SP",
    "SSP SP",
    "DETRAN",
    "Polícia Civil",
    "IFP",
    "Outros"
  ].freeze

  MARITAL_STATUS_OPTIONS = [
    "Solteiro(a)",
    "Casado(a)",
    "União Estável",
    "Divorciado(a)",
    "Viúvo(a)",
    "Separado(a)"
  ].freeze

  ADDRESS_TYPES = [
    "Alameda",
    "Avenida",
    "Estrada",
    "Ladeira",
    "Loteamento",
    "Morro",
    "Parque",
    "Praça",
    "Rodovia",
    "Rua",
    "Travessa",
    "Vale",
    "Via",
    "Viela"
  ].freeze

  enum :role, {
    owner: 0,
    developer: 1,
    builder: 2,
    real_estate_agency: 3,
    broker: 4,
    partner: 5,
    investor: 6
  }, prefix: true

  has_many :habitations, dependent: :nullify
  has_one_attached :profile_image

  validates :name, presence: true
  normalize_phone_fields :phone_primary, :mobile_phone, :residential_phone, :business_phone, :spouse_phone
  validate :cpf_cnpj_must_be_unique
  # Cadastro MANUAL não pode repetir proprietário existente (a base do Vista
  # importa o espelho de lá e fica de fora — vista_code presente). Homônimo
  # legítimo passa informando um CPF diferente dos já cadastrados.
  validate :name_must_not_duplicate_existing, on: :create

  scope :ordered, -> { order(name: :asc) }

  def self.normalized_phone(value)
    Phones::Normalizer.call(value).to_s
  end

  # Cidades cadastradas historicamente vêm com grafias divergentes ("Balneario
  # Camboriu", "balneário Camboriú", "Balneário Camboriú"). Agrupa por chave
  # sem acento/caixa/espaço e devolve uma única grafia canônica por cidade,
  # preferindo a versão acentuada e em caixa de título, para não poluir o
  # autocomplete com dezenas de duplicatas.
  def self.distinct_city_suggestions(limit: 500)
    values = where.not(city: [nil, ""])
      .distinct
      .limit(limit)
      .pluck(:city)
      .map { |city| city.to_s.strip }
      .reject(&:blank?)

    values
      .group_by { |city| I18n.transliterate(city).downcase.gsub(/\s+/, " ").strip }
      .map { |_key, variants| canonical_city_variant(variants) }
      .uniq
      .sort_by { |city| I18n.transliterate(city).downcase }
  end

  def self.canonical_city_variant(variants)
    variants.max_by do |city|
      accents = city.chars.count { |char| I18n.transliterate(char) != char }
      title_case = city == city.split(/(\s+)/).map(&:capitalize).join ? 1 : 0
      [accents, title_case, city.length]
    end
  end

  # LGPD: CPF cifrado at-rest; *_digits com cifra determinística p/ busca por
  # igualdade. Guards mantêm o app funcional pré-migration 20260705000010.
  if (column_names.include?("cpf_cnpj_digits") rescue false)
    encrypts :cpf_cnpj
    encrypts :spouse_cpf_cnpj
    encrypts :cpf_cnpj_digits, deterministic: true
    encrypts :spouse_cpf_cnpj_digits, deterministic: true

    before_validation do
      self.cpf_cnpj_digits = self.class.normalized_cpf_cnpj(cpf_cnpj).presence
      self.spouse_cpf_cnpj_digits = self.class.normalized_cpf_cnpj(spouse_cpf_cnpj).presence
    end
  end

  def self.cpf_digits_searchable?
    (column_names.include?("cpf_cnpj_digits") rescue false)
  end

  def self.normalized_cpf_cnpj(value)
    value.to_s.gsub(/\D/, "")
  end

  def self.find_by_cpf_cnpj(value)
    digits = normalized_cpf_cnpj(value)
    return if digits.blank?

    if cpf_digits_searchable?
      where(cpf_cnpj_digits: digits).order(:id).first
    else
      where("regexp_replace(COALESCE(cpf_cnpj, ''), '\\D', '', 'g') = :digits", digits: digits)
        .order(:id)
        .first
    end
  end

  def self.find_by_phone(value)
    digits = normalized_phone(value)
    return if digits.blank?

    with_normalized_phone(digits).order(:id).first
  end

  def self.find_by_email(value)
    email = value.to_s.strip.downcase
    return if email.blank?

    where("lower(trim(email)) = ?", email).order(:id).first
  end

  scope :with_normalized_phone, ->(digits) {
    where(
      "regexp_replace(COALESCE(phone_primary, ''), '\\D', '', 'g') = :digits OR " \
      "regexp_replace(COALESCE(mobile_phone, ''), '\\D', '', 'g') = :digits OR " \
      "regexp_replace(COALESCE(residential_phone, ''), '\\D', '', 'g') = :digits OR " \
      "regexp_replace(COALESCE(business_phone, ''), '\\D', '', 'g') = :digits",
      digits: digits
    )
  }

  def select_label
    phones = [phone_primary, mobile_phone, residential_phone, business_phone].compact_blank.uniq
    [name, phones.first, email].compact_blank.join(" · ")
  end

  def display_role
    {
      "owner" => "Proprietário",
      "developer" => "Incorporadora",
      "builder" => "Construtora",
      "real_estate_agency" => "Imobiliária",
      "broker" => "Corretor",
      "partner" => "Parceiro",
      "investor" => "Investidor"
    }[role] || role.to_s.humanize
  end

  def profile_image_url
    return nil unless profile_image.attached?

    Rails.application.routes.url_helpers.rails_storage_proxy_path(profile_image, only_path: true)
  end

  private

  def name_must_not_duplicate_existing
    return if vista_code.present?
    return if name.to_s.strip.blank?

    same_name = self.class.where(tenant_id: tenant_id)
                    .where("lower(trim(name)) = ?", name.to_s.strip.downcase)
    same_name = same_name.where.not(id: id) if persisted?
    return unless same_name.exists?

    if cpf_cnpj.present?
      digits = self.class.normalized_cpf_cnpj(cpf_cnpj)
      homonimo_legitimo = same_name.none? do |p|
        existing = self.class.normalized_cpf_cnpj(p.cpf_cnpj)
        existing.blank? || existing == digits
      end
      return if homonimo_legitimo
    end

    errors.add(:name, "já cadastrado — selecione o proprietário existente na lista. Se for outra pessoa com o mesmo nome, informe o CPF para diferenciar.")
  end

  def cpf_cnpj_must_be_unique
    return if vista_code.present?

    digits = self.class.normalized_cpf_cnpj(cpf_cnpj)
    return if digits.blank?

    scope =
      if self.class.cpf_digits_searchable?
        self.class.where(tenant_id: tenant_id, cpf_cnpj_digits: digits)
      else
        self.class.where(tenant_id: tenant_id).where("regexp_replace(COALESCE(cpf_cnpj, ''), '\\D', '', 'g') = :digits", digits: digits)
      end
    scope = scope.where.not(id: id) if persisted?

    errors.add(:cpf_cnpj, "já cadastrado para outro proprietário") if scope.exists?
  end
end
