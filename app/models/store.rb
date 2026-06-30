# frozen_string_literal: true

# Lojas físicas da imobiliária. Entidade de OPERAÇÃO (check-in de corretores,
# distribuição de leads, turnos, raio geofenced). Separada da FooterStore que
# é só a entrada de rodapé do site de marketing. Vínculo opcional via
# `footer_store_id` quando a mesma loja aparece nos dois lugares.
class Store < ApplicationRecord
  include TenantScoped

  extend FriendlyId
  friendly_id :name, use: [:slugged, :finders]

  SRID = 4326 # WGS 84 (GPS padrão)

  belongs_to :director, class_name: "AdminUser", foreign_key: :director_admin_user_id, optional: true
  belongs_to :footer_store, optional: true

  has_many :store_shifts, dependent: :destroy
  has_many :agents, through: :store_shifts, source: :admin_user
  has_many :default_agents, class_name: "AdminUser", foreign_key: :default_store_id, dependent: :nullify

  accepts_nested_attributes_for :store_shifts, allow_destroy: true, reject_if: :all_blank

  validates :name, presence: true
  validates :geofence_radius_meters, numericality: { greater_than: 0, less_than_or_equal_to: 5000 }
  validate :valid_timezone
  validate :valid_coordinates
  validate :director_belongs_to_same_tenant

  scope :active, -> { where(active: true) }
  scope :with_location, -> { where.not(location: nil) }

  # Getters virtuais para latitude e longitude (a coluna real é POINT geography).
  # Ao escrever, o callback before_save gera o POINT.
  attr_accessor :latitude, :longitude

  after_find :extract_coordinates_from_location
  before_save :build_location_from_coordinates

  # Retorna Stores dentro do próprio raio (geofence_radius_meters) a partir
  # de uma coordenada. Não ordena — chamar `.by_distance_from(lat, lng)`
  # se precisar ordenar por proximidade.
  def self.within_geofence_of(lat, lng)
    return none if lat.blank? || lng.blank?

    point_sql = sanitize_sql_array([
      "ST_SetSRID(ST_MakePoint(?, ?), #{SRID})::geography",
      lng.to_f, lat.to_f
    ])

    active
      .with_location
      .where("ST_DWithin(location, #{point_sql}, geofence_radius_meters)")
  end

  # Retorna todas as lojas ativas (com localização) ordenadas por distância
  # de um ponto, incluindo a coluna computada `distance_meters`.
  def self.by_distance_from(lat, lng)
    return none if lat.blank? || lng.blank?

    point_sql = sanitize_sql_array([
      "ST_SetSRID(ST_MakePoint(?, ?), #{SRID})::geography",
      lng.to_f, lat.to_f
    ])

    active
      .with_location
      .select("stores.*, ST_Distance(location, #{point_sql}) AS distance_meters")
      .order(Arel.sql("distance_meters ASC"))
  end

  # Distância em metros de um ponto até o centro da loja. Retorna nil se sem coords.
  def distance_meters_to(lat, lng)
    return nil if location.blank? || lat.blank? || lng.blank?

    result = self.class.connection.select_value(
      self.class.sanitize_sql_for_conditions([
        "SELECT ST_Distance(location, ST_SetSRID(ST_MakePoint(?, ?), #{SRID})::geography) FROM stores WHERE id = ?",
        lng.to_f, lat.to_f, id
      ])
    )
    result&.to_f
  end

  # Testa se um ponto está dentro do geofence da loja.
  def contains?(lat, lng)
    d = distance_meters_to(lat, lng)
    d.present? && d <= geofence_radius_meters
  end

  def timezone_obj
    ActiveSupport::TimeZone[timezone] || Time.zone
  end

  def should_generate_new_friendly_id?
    slug.blank? || name_changed?
  end

  def footer_address_line
    street_line = [address.presence, number.presence].compact.join(", ")
    [street_line.presence, neighborhood.presence].compact.join(" - ")
  end

  def footer_city_line
    [city.presence, state.presence].compact.join(" - ")
  end

  private

  def valid_timezone
    return if timezone.blank?
    return if ActiveSupport::TimeZone[timezone].present?

    errors.add(:timezone, "não é um fuso horário válido")
  end

  def valid_coordinates
    if latitude.present? || longitude.present?
      lat = latitude.to_f
      lng = longitude.to_f
      errors.add(:latitude,  "deve estar entre -90 e 90")   unless lat.between?(-90, 90)
      errors.add(:longitude, "deve estar entre -180 e 180") unless lng.between?(-180, 180)
    end
  end

  def director_belongs_to_same_tenant
    return if director.blank? || tenant.blank? || director.tenant_id == tenant_id

    errors.add(:director, "deve pertencer à mesma conta da loja")
  end

  def extract_coordinates_from_location
    return if location.blank?

    # location vem como string hexadecimal WKB do PostGIS. Pega lat/lng via SQL.
    row = self.class.connection.select_one(
      "SELECT ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng FROM stores WHERE id = #{id}"
    )
    return unless row

    @latitude  = row["lat"]&.to_f
    @longitude = row["lng"]&.to_f
  end

  def build_location_from_coordinates
    return unless latitude.present? && longitude.present?

    # PostGIS aceita EWKT como input. Evita UPDATE extra após INSERT.
    self.location = "SRID=#{SRID};POINT(#{longitude.to_f} #{latitude.to_f})"
  end
end
