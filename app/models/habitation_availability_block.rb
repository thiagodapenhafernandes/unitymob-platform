class HabitationAvailabilityBlock < ApplicationRecord
  include TenantScoped
  belongs_to :habitation

  validates :starts_on, :ends_on, presence: true
  validate :valid_period
  validate :valid_habitation
  validate :no_overlap
  around_save :serialize_periods

  scope :overlapping, ->(from, to) { where("starts_on <= ? AND ends_on >= ?", to, from) }

  private

  def valid_period
    errors.add(:ends_on, "não pode ser anterior à data inicial") if starts_on && ends_on && ends_on < starts_on
  end

  def valid_habitation
    return unless habitation

    errors.add(:habitation, "deve pertencer à mesma conta") if habitation.tenant_id != tenant_id
    errors.add(:habitation, "deve ser de locação diária") unless habitation.daily_rental?
  end

  def conflicting_periods
    self.class.where(tenant_id: tenant_id, habitation_id: habitation_id).where.not(id: id).overlapping(starts_on, ends_on)
  end

  def no_overlap
    return unless starts_on && ends_on && habitation_id

    errors.add(:base, "Já existe um bloqueio nesse período.") if conflicting_periods.exists?
  end

  def serialize_periods
    # O lock do imóvel também serializa inserções concorrentes, antes de existir um bloco.
    habitation.with_lock do
      no_overlap
      raise ActiveRecord::RecordInvalid, self if errors.any?

      yield
    end
  end
end
