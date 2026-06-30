class Tenant < ApplicationRecord
  DEFAULT_SLUG = "default".freeze

  has_many :profiles, dependent: :restrict_with_error
  has_many :admin_users, dependent: :restrict_with_error
  has_many :leads, dependent: :restrict_with_error
  has_many :habitations, dependent: :restrict_with_error
  has_many :tasks, dependent: :restrict_with_error
  has_many :appointments, dependent: :restrict_with_error
  has_many :whatsapp_campaigns, dependent: :restrict_with_error
  has_many :whatsapp_business_integrations, dependent: :restrict_with_error
  has_many :whatsapp_templates, dependent: :restrict_with_error
  has_many :whatsapp_sender_numbers, dependent: :restrict_with_error
  has_many :whatsapp_campaign_recipients, dependent: :restrict_with_error
  has_many :whatsapp_campaign_messages, dependent: :restrict_with_error
  has_many :whatsapp_campaign_unsubscribes, dependent: :restrict_with_error
  has_many :whatsapp_conversations, dependent: :restrict_with_error
  has_many :whatsapp_messages, dependent: :restrict_with_error
  has_many :automation_rules, dependent: :restrict_with_error
  has_many :automation_workflows, dependent: :restrict_with_error
  has_many :automation_workflow_versions, dependent: :restrict_with_error
  has_many :automation_events, dependent: :restrict_with_error
  has_many :automation_executions, dependent: :restrict_with_error
  has_many :automation_execution_steps, dependent: :restrict_with_error
  has_many :distribution_rules, dependent: :restrict_with_error
  has_many :distribution_rule_agents, dependent: :restrict_with_error
  has_many :stores, dependent: :restrict_with_error
  has_many :store_shifts, dependent: :restrict_with_error
  has_many :attribute_options, dependent: :restrict_with_error
  has_many :check_ins, dependent: :restrict_with_error
  has_many :manual_checkin_requests, dependent: :restrict_with_error
  has_many :proprietors, dependent: :restrict_with_error
  has_many :access_audit_logs, dependent: :restrict_with_error
  has_many :access_control_rules, dependent: :restrict_with_error
  has_many :trusted_devices, dependent: :restrict_with_error
  has_many :data_export_audit_logs, dependent: :restrict_with_error
  has_many :checkin_audit_logs, dependent: :restrict_with_error
  has_many :habitation_audit_logs, dependent: :restrict_with_error
  has_many :lead_audit_logs, dependent: :restrict_with_error
  has_many :lead_activities, dependent: :restrict_with_error
  has_many :habitation_exports, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }

  before_validation :normalize_slug
  after_create :ensure_builtin_profiles!

  def self.public_for(slug: nil)
    requested_slug = slug.to_s.strip.presence || ENV["PUBLIC_TENANT_SLUG"].to_s.strip.presence
    active.find_by(slug: requested_slug) || default
  end

  def self.default
    find_or_create_by!(slug: DEFAULT_SLUG) do |tenant|
      tenant.name = "Conta principal"
      tenant.active = true
    end
  end

  def ensure_builtin_profiles!
    profiles.find_or_create_by!(key: "tenant_owner") do |profile|
      profile.name = "Tenant Owner"
      profile.axis = Profile::AXES[:vertical]
      profile.position = 0
      profile.locked = true
      profile.active = true
      profile.permissions = { "admin" => true }
    end

    profiles.find_or_create_by!(key: "agent") do |profile|
      profile.name = "Agent"
      profile.axis = Profile::AXES[:vertical]
      profile.position = 10_000
      profile.locked = true
      profile.active = true
      profile.permissions = {}
    end

    internal_management_profile = ensure_internal_management_profile!

    profiles.find_or_create_by!(key: "gerente") do |profile|
      profile.name = "Gerente"
      profile.axis = Profile::AXES[:vertical]
      profile.position = next_available_vertical_position(preferred: 500)
      profile.active = true
      profile.permissions = Profile.default_permissions_for("Gerente")
    end

    profiles.find_or_create_by!(key: "administrativo") do |profile|
      profile.name = "Administrativo"
      profile.axis = Profile::AXES[:horizontal]
      profile.vertical_profile = internal_management_profile
      profile.active = true
      profile.permissions = Profile.default_permissions_for("Administrativo")
    end
  end

  private

  def ensure_internal_management_profile!
    profiles.vertical.find_or_create_by!(name: Profile::INTERNAL_MANAGEMENT_PROFILE_NAME) do |profile|
      profile.axis = Profile::AXES[:vertical]
      profile.position = next_available_vertical_position(preferred: Profile::INTERNAL_MANAGEMENT_PROFILE_POSITION)
      profile.active = true
      profile.permissions = Profile.default_permissions_for("Administrativo")
    end
  end

  def next_available_vertical_position(preferred:)
    used_positions = profiles.vertical.where.not(position: nil).pluck(:position).map(&:to_i)
    candidate = preferred
    candidate += 100 while used_positions.include?(candidate) && candidate < 9_900
    candidate
  end

  def normalize_slug
    self.slug = name.to_s.parameterize if slug.blank? && name.present?
  end
end
