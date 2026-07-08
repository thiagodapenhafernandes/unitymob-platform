# frozen_string_literal: true

# Registro de check-in/check-out de um corretor numa loja.
# Unicidade: apenas 1 check-in ativo por admin_user (via partial unique index).
class CheckIn < ApplicationRecord
  include TenantScoped

  SRID = 4326

  enum status: {
    active:                     0,
    closed_manual:              1,
    closed_auto_shift_end:      2,
    closed_auto_out_of_radius:  3,
    closed_admin_force:         4,
    # Fechado por inatividade (sem pings recentes) — NÃO significa "fora do
    # raio". O PWA só envia pings em foreground, então tela apagada/app em
    # background gera silêncio sem que o corretor tenha saído do local.
    closed_auto_no_signal:      5
  }

  belongs_to :admin_user
  belongs_to :store
  belongs_to :store_shift, optional: true
  has_many :location_pings, dependent: :delete_all

  validates :checked_in_at, presence: true
  validate :associations_belong_to_same_tenant

  scope :today, -> { where(checked_in_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :suspicious, -> { where(suspicious: true) }
  scope :trustworthy, -> { where(suspicious: false) }
  scope :for_arrival_statuses, ->(statuses) { where(status_chegada: Array(statuses).compact_blank) }

  def flag_suspicious!(reasons:)
    existing = Array(suspicious_reasons)
    merged = (existing + Array(reasons)).uniq
    update!(suspicious: true, suspicious_reasons: merged)
  end

  attr_accessor :checkin_latitude, :checkin_longitude, :checkout_latitude, :checkout_longitude

  after_find  :extract_coordinates
  before_save :build_locations_from_coordinates

  def duration
    (checked_out_at || Time.current) - checked_in_at
  end

  def closed?
    !active?
  end

  # Fecha o check-in com razão + coordenadas opcionais.
  def force_close!(reason:, lat: nil, lng: nil, ip: nil, accuracy: nil)
    self.checked_out_at = Time.current
    self.status = reason
    self.checkout_latitude = lat if lat
    self.checkout_longitude = lng if lng
    self.checkout_ip = ip if ip
    self.checkout_accuracy_meters = accuracy if accuracy
    save!
  end

  private

  def extract_coordinates
    row = self.class.connection.select_one(<<~SQL)
      SELECT
        ST_Y(checkin_location::geometry) AS in_lat,
        ST_X(checkin_location::geometry) AS in_lng,
        ST_Y(checkout_location::geometry) AS out_lat,
        ST_X(checkout_location::geometry) AS out_lng
      FROM check_ins WHERE id = #{id}
    SQL
    return unless row

    @checkin_latitude  = row["in_lat"]&.to_f
    @checkin_longitude = row["in_lng"]&.to_f
    @checkout_latitude = row["out_lat"]&.to_f
    @checkout_longitude = row["out_lng"]&.to_f
  end

  def build_locations_from_coordinates
    if checkin_latitude.present? && checkin_longitude.present?
      self.checkin_location = "SRID=#{SRID};POINT(#{checkin_longitude.to_f} #{checkin_latitude.to_f})"
    end
    if checkout_latitude.present? && checkout_longitude.present?
      self.checkout_location = "SRID=#{SRID};POINT(#{checkout_longitude.to_f} #{checkout_latitude.to_f})"
    end
  end

  def associations_belong_to_same_tenant
    %i[admin_user store store_shift].each do |association_name|
      record = public_send(association_name)
      next if record.blank? || tenant.blank? || record.tenant_id == tenant_id

      errors.add(association_name, "deve pertencer à mesma conta do check-in")
    end
  end
end
