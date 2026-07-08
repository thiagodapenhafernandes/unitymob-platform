class AccessControlRule < ApplicationRecord
  include TenantScoped

  RULE_TYPES = {
    "block_ip" => "IP bloqueado",
    "allow_ip" => "IP permitido",
    "ignore_tracking_ip" => "Ignorar nas métricas"
  }.freeze

  SCOPE_TYPES = {
    "global" => "Todos",
    "profile" => "Perfil",
    "user" => "Usuário"
  }.freeze

  belongs_to :profile, optional: true
  belongs_to :admin_user, optional: true
  belongs_to :created_by, class_name: "AdminUser", optional: true

  validates :name, :rule_type, :scope_type, :ip_value, presence: true
  validates :rule_type, inclusion: { in: RULE_TYPES.keys }
  validates :scope_type, inclusion: { in: SCOPE_TYPES.keys }
  validate :valid_ip_value
  validate :scope_target_matches_scope_type
  validate :scope_target_tenant_consistency

  scope :enabled, -> { where(enabled: true) }
  scope :recent, -> { order(created_at: :desc) }

  def self.matching_ip(ip)
    return none if ip.blank?

    enabled.select { |rule| rule.matches_ip?(ip) }
  end

  def self.matching_ip_for_tenant(ip, tenant)
    return none if tenant.blank?

    for_tenant(tenant).matching_ip(ip)
  end

  def matches_ip?(ip)
    IPAddr.new(ip_value).include?(IPAddr.new(ip.to_s))
  rescue IPAddr::InvalidAddressError
    false
  end

  def applies_to_user?(user)
    case scope_type
    when "global"
      true
    when "profile"
      profile.present? && user.present? && AdminUser.where(id: user.id).matching_access_profile(profile).exists?
    when "user"
      admin_user_id.present? && admin_user_id == user&.id
    else
      false
    end
  end

  def rule_type_label
    RULE_TYPES[rule_type] || rule_type.to_s.humanize
  end

  def scope_label
    case scope_type
    when "profile"
      profile&.name || "Perfil removido"
    when "user"
      admin_user&.name || admin_user&.email || "Usuário removido"
    else
      SCOPE_TYPES[scope_type] || scope_type.to_s.humanize
    end
  end

  private

  def valid_ip_value
    IPAddr.new(ip_value.to_s)
  rescue IPAddr::InvalidAddressError
    errors.add(:ip_value, "deve ser um IP ou faixa CIDR válida")
  end

  def scope_target_matches_scope_type
    errors.add(:profile, "deve ser informado") if scope_type == "profile" && profile_id.blank?
    errors.add(:admin_user, "deve ser informado") if scope_type == "user" && admin_user_id.blank?
  end

  def scope_target_tenant_consistency
    errors.add(:profile, "deve pertencer ao mesmo Tenant") if profile.present? && profile.tenant_id != tenant_id
    errors.add(:admin_user, "deve pertencer ao mesmo Tenant") if admin_user.present? && admin_user.tenant_id != tenant_id
    errors.add(:created_by, "deve pertencer ao mesmo Tenant") if created_by.present? && created_by.tenant_id != tenant_id
  end
end
