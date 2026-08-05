class TenantDomain < ApplicationRecord
  SSL_MODES = {
    "not_configured" => "Não configurado",
    "shared_wildcard" => "Wildcard compartilhado",
    "external_certificate" => "Certificado externo"
  }.freeze

  HOSTNAME_FORMAT = /\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}\z/

  belongs_to :tenant

  before_validation :normalize_hostname
  before_validation :activate_primary_domain
  before_save :unset_other_primary_domains, if: -> { primary_domain? && will_save_change_to_primary_domain? }

  validates :hostname,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: HOSTNAME_FORMAT, message: "deve ser um domínio válido, sem protocolo ou caminho" }
  validates :ssl_mode, inclusion: { in: SSL_MODES.keys }

  scope :active, -> { where(active: true) }
  scope :primary_first, -> { order(primary_domain: :desc, active: :desc, hostname: :asc) }

  def self.ssl_mode_options
    SSL_MODES.map { |value, label| [label, value] }
  end

  def self.normalize_host(value)
    host = value.to_s.strip.downcase
    host = host.sub(/\Ahttps?:\/\//, "")
    host = host.split("/").first.to_s
    host = host.split("@").last.to_s
    host = host.split(":").first.to_s
    host.delete_suffix(".")
  end

  def self.find_for_host(value)
    normalized = normalize_host(value)
    return if normalized.blank?

    active.includes(:tenant).find_by(hostname: normalized)
  end

  def ssl_mode_label
    SSL_MODES.fetch(ssl_mode, ssl_mode)
  end

  def primary?
    primary_domain?
  end

  private

  def normalize_hostname
    self.hostname = self.class.normalize_host(hostname)
  end

  def activate_primary_domain
    self.active = true if primary_domain?
  end

  def unset_other_primary_domains
    tenant.tenant_domains.where.not(id: id).update_all(primary_domain: false, updated_at: Time.current)
  end
end
