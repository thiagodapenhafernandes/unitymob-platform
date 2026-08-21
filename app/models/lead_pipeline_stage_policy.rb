class LeadPipelineStagePolicy < ApplicationRecord
  include TenantScoped

  VISIBLE_ROLES = {
    "broker" => "Corretor",
    "manager" => "Gestor",
    "administrative" => "Administrativo",
    "admin" => "Administrador"
  }.freeze

  QUALIFICATION_OPTIONS = {
    "qualified" => "Qualificado",
    "disqualified" => "Desqualificado",
    "missing_data" => "Sem dados"
  }.freeze

  DEFAULT_VISIBLE_ROLES = %w[broker manager admin].freeze
  DEFAULT_QUALIFICATION_OPTIONS = QUALIFICATION_OPTIONS.keys.freeze

  belongs_to :lead_pipeline_stage

  validates :lead_pipeline_stage_id, uniqueness: { scope: :tenant_id }
  validates :future_activity_limit_days,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true
  validate :records_must_belong_to_tenant

  before_validation :normalize_arrays

  def self.default_attributes
    {
      visible_to_roles: DEFAULT_VISIBLE_ROLES,
      qualification_options: DEFAULT_QUALIFICATION_OPTIONS,
      divergence_queue_enabled: false,
      qualification_enabled: false,
      allowed_archive_reason_ids: [],
      settings: {}
    }
  end

  def visible_role_labels
    visible_to_roles.filter_map { |role| VISIBLE_ROLES[role.to_s] }
  end

  def visible_to_admin_user?(admin_user)
    return true if admin_user.blank? || admin_user.admin?

    visible_to_roles.include?(self.class.role_for(admin_user))
  end

  def self.role_for(admin_user)
    profile = admin_user&.access_profile&.root_vertical_profile || admin_user&.profile&.root_vertical_profile
    return "admin" if admin_user&.admin? || profile&.tenant_owner?
    return "manager" if profile&.gerente?
    return "administrative" if profile&.administrativo?

    "broker"
  end

  private

  def normalize_arrays
    self.visible_to_roles = normalize_list(visible_to_roles, VISIBLE_ROLES.keys)
    self.visible_to_roles = DEFAULT_VISIBLE_ROLES if visible_to_roles.blank?
    self.qualification_options = normalize_list(qualification_options, QUALIFICATION_OPTIONS.keys)
    self.qualification_options = DEFAULT_QUALIFICATION_OPTIONS if qualification_options.blank?
    self.allowed_archive_reason_ids = Array(allowed_archive_reason_ids).filter_map do |id|
      Integer(id)
    rescue ArgumentError, TypeError
      nil
    end.uniq
    self.settings = {} unless settings.is_a?(Hash)
  end

  def normalize_list(values, allowed)
    Array(values).map(&:to_s).select { |value| allowed.include?(value) }.uniq
  end

  def records_must_belong_to_tenant
    return if tenant_id.blank? || lead_pipeline_stage.blank?

    errors.add(:lead_pipeline_stage, "deve pertencer ao mesmo Tenant") if lead_pipeline_stage.tenant_id != tenant_id
  end
end
