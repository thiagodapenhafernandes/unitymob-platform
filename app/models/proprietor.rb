class Proprietor < ApplicationRecord
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
  validate :cpf_cnpj_must_be_unique

  scope :ordered, -> { order(name: :asc) }

  def self.normalized_phone(value)
    value.to_s.gsub(/\D/, "")
  end

  def self.normalized_cpf_cnpj(value)
    value.to_s.gsub(/\D/, "")
  end

  def self.find_by_cpf_cnpj(value)
    digits = normalized_cpf_cnpj(value)
    return if digits.blank?

    where("regexp_replace(COALESCE(cpf_cnpj, ''), '\\D', '', 'g') = :digits", digits: digits)
      .order(:id)
      .first
  end

  def self.find_by_phone(value)
    digits = normalized_phone(value)
    return if digits.blank?

    where(
      "regexp_replace(COALESCE(phone_primary, ''), '\\D', '', 'g') = :digits OR " \
      "regexp_replace(COALESCE(mobile_phone, ''), '\\D', '', 'g') = :digits OR " \
      "regexp_replace(COALESCE(residential_phone, ''), '\\D', '', 'g') = :digits OR " \
      "regexp_replace(COALESCE(business_phone, ''), '\\D', '', 'g') = :digits",
      digits: digits
    ).order(:id).first
  end

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

  def cpf_cnpj_must_be_unique
    return if vista_code.present?

    digits = self.class.normalized_cpf_cnpj(cpf_cnpj)
    return if digits.blank?

    scope = self.class.where("regexp_replace(COALESCE(cpf_cnpj, ''), '\\D', '', 'g') = :digits", digits: digits)
    scope = scope.where.not(id: id) if persisted?

    errors.add(:cpf_cnpj, "já cadastrado para outro proprietário") if scope.exists?
  end
end
