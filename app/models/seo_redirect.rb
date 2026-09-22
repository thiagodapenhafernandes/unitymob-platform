class SeoRedirect < ApplicationRecord
  include TenantScoped
  VALID_STATUS_CODES = [301, 302, 307, 308].freeze

  belongs_to :created_by_admin_user, class_name: "AdminUser", optional: true

  validates :from_path, :to_path, presence: true
  validates :from_path, uniqueness: { scope: :tenant_id }
  validates :status_code, inclusion: { in: VALID_STATUS_CODES }
  validate :paths_are_different
  validate :to_path_is_internal_or_tenant_domain

  before_validation :normalize_paths

  scope :active, -> { where(active: true) }
  scope :recent, -> { order(updated_at: :desc) }

  def register_hit!
    increment!(:hit_count)
    update_column(:last_hit_at, Time.current)
  end

  private

  def normalize_paths
    self.from_path = normalize_path(from_path)
    self.to_path = normalize_path(to_path)
  end

  def normalize_path(value)
    value = value.to_s.strip
    return if value.blank?
    return value if value.start_with?("http://", "https://")

    value.start_with?("/") ? value : "/#{value}"
  end

  def paths_are_different
    errors.add(:to_path, "deve ser diferente da origem") if from_path.present? && from_path == to_path
  end

  def to_path_is_internal_or_tenant_domain
    return if to_path.blank?

    uri = URI.parse(to_path.to_s)
    return if uri.relative? && to_path.start_with?("/") && !to_path.start_with?("//")
    return if uri.is_a?(URI::HTTP) && tenant_redirect_host?(uri.host)

    errors.add(:to_path, "deve ser um caminho interno ou uma URL de domínio da conta")
  rescue URI::InvalidURIError
    errors.add(:to_path, "deve ser um caminho interno ou uma URL de domínio da conta")
  end

  def tenant_redirect_host?(host)
    normalized_host = TenantDomain.normalize_host(host)
    return false if normalized_host.blank? || tenant.blank?

    comparable_host = normalized_host.delete_prefix("www.")
    tenant.tenant_domains.active.pluck(:hostname).any? do |hostname|
      TenantDomain.normalize_host(hostname).delete_prefix("www.") == comparable_host
    end
  end
end
