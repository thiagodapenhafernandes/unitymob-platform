class DataExportAuditLog < ApplicationRecord
  include TenantScoped

  EXPORT_TYPES = {
    "csv_export" => "Exportação CSV",
    "print_report" => "Relatório/Impressão"
  }.freeze

  RESOURCE_NAMES = {
    "habitations" => "Imóveis",
    "proprietors" => "Proprietários",
    "captacoes" => "Captações"
  }.freeze

  belongs_to :admin_user, optional: true

  validates :export_type, :resource_name, :format, presence: true
  validates :export_type, inclusion: { in: EXPORT_TYPES.keys }
  validates :resource_name, inclusion: { in: RESOURCE_NAMES.keys }
  validates :record_count, :selected_count, numericality: { greater_than_or_equal_to: 0 }

  self.record_timestamps = false
  before_create :set_created_at

  scope :recent, -> { order(created_at: :desc) }

  def readonly?
    persisted?
  end

  def actor_name
    tenant_admin_user&.then { |user| user.name.presence || user.email.presence } || "Usuário não identificado"
  end

  def export_type_label
    EXPORT_TYPES[export_type] || export_type.to_s.humanize
  end

  def resource_label
    RESOURCE_NAMES[resource_name] || resource_name.to_s.humanize
  end

  private

  def set_created_at
    self.created_at ||= Time.current
  end

  def tenant_admin_user
    return if admin_user_id.blank?

    tenant.admin_users.find_by(id: admin_user_id)
  end
end
