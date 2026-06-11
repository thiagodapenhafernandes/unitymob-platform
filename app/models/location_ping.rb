# frozen_string_literal: true

# Um ping de GPS durante um check-in ativo. Enviado pelo PWA a cada 60-90s
# enquanto o app está em foreground.
#
# inside_radius é cacheado no insert (calculado com PostGIS contra o raio
# da loja do check-in) para evitar recalcular em cada query de admin.
class LocationPing < ApplicationRecord
  SRID = 4326

  belongs_to :check_in
  belongs_to :admin_user

  validates :recorded_at, presence: true

  scope :recent, -> { order(recorded_at: :desc) }

  attr_accessor :latitude, :longitude

  after_find  :extract_coordinates
  before_save :build_location_from_coordinates

  def coordinates_pair
    [latitude, longitude]
  end

  private

  def extract_coordinates
    row = self.class.connection.select_one(
      "SELECT ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng FROM location_pings WHERE id = #{id}"
    )
    return unless row

    @latitude = row["lat"]&.to_f
    @longitude = row["lng"]&.to_f
  end

  def build_location_from_coordinates
    return unless latitude.present? && longitude.present?
    self.location = "SRID=#{SRID};POINT(#{longitude.to_f} #{latitude.to_f})"
  end
end
