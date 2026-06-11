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

  scope :ordered, -> { order(name: :asc) }

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

    Rails.application.routes.url_helpers.rails_blob_path(profile_image, only_path: true)
  end
end
