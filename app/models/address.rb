class Address < ApplicationRecord
  # Coordenada tirada do centro do bairro (o mapa não conhecia a rua). O mapa
  # público mostra só região aproximada; nova geocodificação pode substituir.
  NEIGHBORHOOD_PRECISION = "neighborhood".freeze

  belongs_to :addressable, polymorphic: true

  # Higiene vinda do Vista: espaços sobrando criavam variantes de bairro/cidade
  before_save do
    self.bairro = bairro.to_s.squish.presence if will_save_change_to_bairro?
    self.cidade = cidade.to_s.squish.presence if respond_to?(:cidade) && will_save_change_to_cidade?
  end
  before_validation :normalize_imediacoes
  # Coordenada ajustada à mão (pino no admin, import) deixa de ser aproximada.
  before_save do
    if (will_save_change_to_latitude? || will_save_change_to_longitude?) && !will_save_change_to_coordinates_precision?
      self.coordinates_precision = nil
    end
  end
  after_commit :clear_habitation_public_filter_cache, if: :habitation_location_cache_relevant?

  # Validations
  validates :logradouro, :bairro, :cidade, :uf, presence: true
  validates :uf, length: { is: 2 }
  validates :cep, format: { with: /\A\d{5}-?\d{3}\z/, message: "formato inválido (00000-000)" }, allow_blank: true
  
  after_commit :schedule_missing_coordinates, on: [:create, :update]

  def neighborhood_coordinates?
    coordinates_precision == NEIGHBORHOOD_PRECISION
  end

  # Sem coordenada, ou só com o centro do bairro: vale tentar geocodificar.
  def coordinates_improvable?
    latitude.blank? || longitude.blank? || neighborhood_coordinates?
  end

  def schedule_missing_coordinates
    return unless addressable_type == "Habitation" && coordinates_improvable?
    return unless previous_changes.keys.intersect?(%w[id logradouro numero bairro cidade uf cep])

    setting = GoogleMapsIntegrationSetting.for(addressable.tenant)
    return unless setting.configured? # Google ou Leaflet (Nominatim)

    HabitationGeocodeJob.perform_later(addressable_id, tenant_id: addressable.tenant_id)
  end

  def full_address
    [logradouro, numero, bairro, cidade, uf, pais].compact.join(', ')
  end

  def imediacoes=(value)
    super(normalize_list_value(value))
  end

  private

  def normalize_imediacoes
    self.imediacoes = normalize_list_value(imediacoes)
  end

  def habitation_location_cache_relevant?
    addressable_type == "Habitation" &&
      (previous_changes.key?("cidade") || previous_changes.key?("bairro") || previous_changes.key?("addressable_id"))
  end

  def clear_habitation_public_filter_cache
    tenant_id = addressable&.tenant_id
    return if tenant_id.blank?

    Habitation.clear_public_filter_cache_for_tenant(tenant_id)
  end

  def normalize_list_value(value)
    raw_items =
      case value
      when Array
        value
      when String
        value.split(/[,\n;]+/)
      else
        Array(value)
      end

    raw_items.map { |item| item.to_s.strip }
             .reject(&:blank?)
             .uniq
  end
end
