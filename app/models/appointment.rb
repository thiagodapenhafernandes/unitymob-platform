class Appointment < ApplicationRecord
  include TenantScoped

  KINDS = {
    "visita" => "Visita",
    "reuniao" => "Reunião",
    "ligacao" => "Ligação",
    "outro" => "Outro"
  }.freeze
  STATUSES = %w[agendado realizado cancelado].freeze

  belongs_to :lead, optional: true
  belongs_to :admin_user
  belongs_to :habitation, optional: true

  validates :title, presence: true
  validates :starts_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :kind, inclusion: { in: KINDS.keys }
  validate :associations_belong_to_same_tenant

  scope :upcoming, -> { where("starts_at >= ?", Time.current.beginning_of_day).order(:starts_at) }
  scope :for_day, ->(date) { where(starts_at: date.beginning_of_day..date.end_of_day) }
  scope :between, ->(a, b) { where(starts_at: a..b) }
  scope :ordered, -> { order(:starts_at) }

  def kind_label = KINDS[kind] || kind
  def realizado? = status == "realizado"
  def cancelado? = status == "cancelado"
  def agendado? = status == "agendado"

  private

  def associations_belong_to_same_tenant
    tenant_association_errors_for(
      admin_user: admin_user,
      lead: lead,
      habitation: habitation
    )
  end

  def tenant_association_errors_for(associations)
    associations.each do |name, record|
      next if record.blank? || tenant.blank? || record.tenant_id == tenant_id

      errors.add(name, "deve pertencer à mesma conta do compromisso")
    end
  end
end
