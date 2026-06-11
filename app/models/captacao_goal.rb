# frozen_string_literal: true

# Meta de captação por tipo e período. Usada pelo dashboard para calcular
# progresso contra o intervalo filtrado pelo administrador.
class CaptacaoGoal < ApplicationRecord
  enum kind: { venda: 0, locacao: 1 }, _prefix: true

  before_validation :sync_year_from_start_date

  validates :year, presence: true
  validates :start_date, :end_date, presence: true
  validates :target, numericality: { greater_than: 0 }
  validate :end_date_after_start_date
  validate :period_must_not_overlap_same_kind

  scope :for_year, ->(y) { where(year: y) }
  scope :overlapping_period, ->(start_date, end_date) {
    where("start_date <= ? AND end_date >= ?", end_date, start_date)
  }

  def self.current_target(kind:, start_date: nil, end_date: nil, year: nil)
    goals_for_period(kind: kind, start_date: start_date, end_date: end_date, year: year).sum(:target).to_i
  end

  def self.current_foco(kind:, start_date: nil, end_date: nil, year: nil)
    goals_for_period(kind: kind, start_date: start_date, end_date: end_date, year: year).order(:start_date).first
  end

  def self.goals_for_period(kind:, start_date: nil, end_date: nil, year: nil)
    if start_date.blank? || end_date.blank?
      base_year = year.presence || Date.current.year
      start_date = Date.new(base_year.to_i, 1, 1)
      end_date = Date.new(base_year.to_i, 12, 31)
    end

    where(kind: kind).overlapping_period(start_date.to_date, end_date.to_date)
  end

  def period_label
    return "" if start_date.blank? || end_date.blank?

    "#{I18n.l(start_date)} a #{I18n.l(end_date)}"
  end

  private

  def sync_year_from_start_date
    self.year = start_date.year if start_date.present?
  end

  def end_date_after_start_date
    return if start_date.blank? || end_date.blank?
    return if end_date >= start_date

    errors.add(:end_date, "deve ser maior ou igual à data inicial")
  end

  def period_must_not_overlap_same_kind
    return if kind.blank? || start_date.blank? || end_date.blank?

    overlapping = self.class
                      .where(kind: kind)
                      .where.not(id: id)
                      .overlapping_period(start_date, end_date)
                      .exists?
    return unless overlapping

    errors.add(:base, "Já existe uma meta de #{kind_label} com período sobreposto")
  end

  def kind_label
    kind_venda? ? "venda" : "locação"
  end
end
