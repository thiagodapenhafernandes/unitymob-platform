# frozen_string_literal: true

# Turno de um corretor em uma loja específica, por dia da semana.
# Ex: Carlos trabalha na Loja Centro às segundas-feiras das 09:00 às 18:00.
# Múltiplos turnos permitem escalas como "seg, qua, sex" via rows separados.
class StoreShift < ApplicationRecord
  DAYS_OF_WEEK = {
    0 => "Domingo",
    1 => "Segunda-feira",
    2 => "Terça-feira",
    3 => "Quarta-feira",
    4 => "Quinta-feira",
    5 => "Sexta-feira",
    6 => "Sábado"
  }.freeze

  belongs_to :store
  belongs_to :admin_user

  validates :day_of_week, inclusion: { in: 0..6 }
  validates :start_time, :end_time, presence: true
  validate :end_time_after_start_time

  scope :active, -> { where(active: true) }
  scope :for_day, ->(dow) { where(day_of_week: dow) }

  # Retorna shifts que estão "ativos agora" considerando o timezone da loja.
  # Uso: StoreShift.active_now_for(admin_user)
  scope :active_now_for, ->(admin_user) {
    now = Time.current
    in_any_tz = Store.select(:timezone).distinct.pluck(:timezone).map do |tz|
      local = now.in_time_zone(tz)
      { tz: tz, dow: local.wday, time_of_day: local.strftime("%H:%M:%S") }
    end
    # Monta um OR por timezone distinto (geralmente só 1 no Brasil).
    clauses = in_any_tz.map { |q|
      "(stores.timezone = '#{q[:tz]}' AND store_shifts.day_of_week = #{q[:dow]}" \
      " AND store_shifts.start_time <= '#{q[:time_of_day]}'" \
      " AND store_shifts.end_time > '#{q[:time_of_day]}')"
    }.join(" OR ")
    joins(:store).active.where(admin_user: admin_user).where(clauses)
  }

  def day_name
    DAYS_OF_WEEK[day_of_week]
  end

  def label
    "#{day_name} • #{start_time.strftime('%H:%M')}–#{end_time.strftime('%H:%M')}"
  end

  # Verifica se este turno está ativo no horário informado (considerando tz da loja).
  def active_at?(time = Time.current)
    return false unless active?

    local = time.in_time_zone(store.timezone_obj)
    return false unless local.wday == day_of_week

    tod = local.strftime("%H:%M:%S")
    tod >= start_time.strftime("%H:%M:%S") && tod < end_time.strftime("%H:%M:%S")
  end

  private

  def end_time_after_start_time
    return if start_time.blank? || end_time.blank?

    errors.add(:end_time, "deve ser depois do horário inicial") if end_time <= start_time
  end
end
