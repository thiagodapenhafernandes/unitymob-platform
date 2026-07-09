# frozen_string_literal: true

# Lojas físicas da imobiliária. Entidade de OPERAÇÃO (check-in de corretores,
# distribuição de leads, turnos, raio geofenced). Separada da FooterStore que
# é só a entrada de rodapé do site de marketing. Vínculo opcional via
# `footer_store_id` quando a mesma loja aparece nos dois lugares.
class Store < ApplicationRecord
  include TenantScoped
  include PhoneNormalizable

  extend FriendlyId
  friendly_id :name, use: [:slugged, :finders]

  SRID = 4326 # WGS 84 (GPS padrão)
  OPERATIONAL_SHIFTS = %w[manha tarde unico].freeze
  OPERATIONAL_PERIODS = %w[entrada pos_risca fora_roleta].freeze
  ARRIVAL_STATUS_LABELS = {
    "sorteio" => "Entrada",
    "pos_risca" => "Pós-risca",
    "fora_horario" => "Fora da roleta"
  }.freeze

  belongs_to :director, class_name: "AdminUser", foreign_key: :director_admin_user_id, optional: true
  belongs_to :footer_store, optional: true

  has_many :store_shifts, dependent: :destroy
  has_many :agents, through: :store_shifts, source: :admin_user
  has_many :default_agents, class_name: "AdminUser", foreign_key: :default_store_id, dependent: :nullify

  accepts_nested_attributes_for :store_shifts, allow_destroy: true, reject_if: :all_blank

  validates :name, presence: true
  normalize_phone_fields :phone
  validates :geofence_radius_meters, numericality: { greater_than: 0, less_than_or_equal_to: 5000 }
  validate :valid_timezone
  validate :valid_coordinates
  validate :director_belongs_to_same_tenant
  validate :footer_store_reference_is_valid

  scope :active, -> { where(active: true) }
  scope :with_location, -> { where.not(location: nil) }

  # Getters virtuais para latitude e longitude (a coluna real é POINT geography).
  # Ao escrever, o callback before_save gera o POINT.
  attr_accessor :latitude, :longitude

  after_find :extract_coordinates_from_location
  before_save :build_location_from_coordinates
  before_validation :ensure_turnos_config_structure, if: :has_turnos_config_column?

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

  def self.default_turnos_config
    {
      "manha" => {
        "ativo" => true,
        "entrada" => { "inicio" => "08:00", "fim" => "08:30" },
        "pos_risca" => { "inicio" => "08:30", "fim" => "09:00" },
        "fora_roleta" => { "inicio" => "09:00", "fim" => "12:00" },
        "checkout" => { "delay_seconds" => 0, "remove_from_queue" => false }
      },
      "tarde" => {
        "ativo" => true,
        "entrada" => { "inicio" => "13:00", "fim" => "13:30" },
        "pos_risca" => { "inicio" => "13:30", "fim" => "14:00" },
        "fora_roleta" => { "inicio" => "14:00", "fim" => "18:00" },
        "checkout" => { "delay_seconds" => 0, "remove_from_queue" => false }
      },
      "unico" => {
        "ativo" => false,
        "entrada" => { "inicio" => "08:00", "fim" => "08:30" },
        "pos_risca" => { "inicio" => "08:30", "fim" => "09:00" },
        "fora_roleta" => { "inicio" => "09:00", "fim" => "18:00" },
        "checkout" => { "delay_seconds" => 0, "remove_from_queue" => false }
      }
    }
  end

  def operational_turnos_config
    return self.class.default_turnos_config unless has_turnos_config_column?

    self.class.default_turnos_config.deep_merge((turnos_config.presence || {}).to_h)
  end

  def current_operational_shift(at = Time.current)
    local_minutes = minutes_for(at.in_time_zone(timezone_obj))

    OPERATIONAL_SHIFTS.find do |shift_key|
      shift_config = operational_turnos_config[shift_key]
      next false unless ActiveModel::Type::Boolean.new.cast(shift_config["ativo"])

      start_minutes = parse_shift_minutes(shift_config.dig("entrada", "inicio"))
      end_minutes = parse_shift_minutes(shift_config.dig("fora_roleta", "fim"))
      time_in_operational_range?(local_minutes, start_minutes, end_minutes)
    end
  end

  def current_arrival_status(at = Time.current)
    shift_key = current_operational_shift(at)
    return nil if shift_key.blank?

    arrival_status_for_shift(shift_key, at)
  end

  def arrival_status_for_shift(shift_key, at = Time.current)
    shift_config = operational_turnos_config[shift_key.to_s]
    return nil if shift_config.blank?

    local_minutes = minutes_for(at.in_time_zone(timezone_obj))
    return "sorteio" if minutes_between?(local_minutes, shift_config.dig("entrada", "inicio"), shift_config.dig("entrada", "fim"))
    return "pos_risca" if minutes_between?(local_minutes, shift_config.dig("pos_risca", "inicio"), shift_config.dig("pos_risca", "fim"))
    return "fora_horario" if minutes_between?(local_minutes, shift_config.dig("fora_roleta", "inicio"), shift_config.dig("fora_roleta", "fim"))

    nil
  end

  def operational_shift_active_at?(at = Time.current)
    current_operational_shift(at).present?
  end

  def operational_shift_end_time(shift_key, reference_time = Time.current)
    shift_config = operational_turnos_config[shift_key.to_s]
    end_value = shift_config&.dig("fora_roleta", "fim")
    return nil if end_value.blank?

    hour, minute = end_value.to_s.split(":").map(&:to_i)
    reference_local = reference_time.in_time_zone(timezone_obj)

    Time.use_zone(timezone_obj) do
      Time.zone.local(reference_local.year, reference_local.month, reference_local.day, hour, minute)
    end
  rescue StandardError
    nil
  end

  def auto_checkout_delay_for(shift_key)
    checkout_config = operational_turnos_config.dig(shift_key.to_s, "checkout")
    return auto_checkout_after_minutes.to_i.minutes unless checkout_config.is_a?(Hash) && checkout_config.key?("delay_seconds")

    checkout_config["delay_seconds"].to_i.seconds
  end

  def remove_from_queue_after_checkout?(shift_key)
    ActiveModel::Type::Boolean.new.cast(
      operational_turnos_config.dig(shift_key.to_s, "checkout", "remove_from_queue")
    )
  end

  private

  def has_turnos_config_column?
    has_attribute?(:turnos_config)
  end

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

  # FooterStore é uma entidade GLOBAL (marketing/rodapé do site): a tabela
  # footer_stores não tem tenant_id — pertence a um footer_setting singleton
  # compartilhado. Portanto não há vínculo de tenant a validar. Ainda assim,
  # footer_store_id chega cru dos params (store_params permite :footer_store_id),
  # então rejeitamos IDs inexistentes para evitar vínculo pendente/inválido.
  def footer_store_reference_is_valid
    return if footer_store_id.blank?
    return if FooterStore.exists?(id: footer_store_id)

    errors.add(:footer_store_id, "referência de loja de rodapé inválida")
  end

  def ensure_turnos_config_structure
    self.turnos_config = self.class.default_turnos_config.deep_merge((turnos_config.presence || {}).to_h)
  end

  def parse_shift_minutes(value)
    return nil if value.blank?

    hour, minute = value.to_s.split(":").map(&:to_i)
    (hour * 60) + minute
  end

  def minutes_for(time)
    (time.hour * 60) + time.min
  end

  def minutes_between?(minutes, start_value, end_value)
    time_in_operational_range?(minutes, parse_shift_minutes(start_value), parse_shift_minutes(end_value))
  end

  def time_in_operational_range?(minutes, start_minutes, end_minutes)
    return false if minutes.nil? || start_minutes.nil? || end_minutes.nil?

    if end_minutes < start_minutes
      minutes >= start_minutes || minutes <= end_minutes
    else
      minutes >= start_minutes && minutes <= end_minutes
    end
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
