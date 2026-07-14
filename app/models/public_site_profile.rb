class PublicSiteProfile
  include ActiveModel::Model
  include ActiveModel::Attributes

  PREFIX = "public_site.profile".freeze
  FIELDS = %i[
    primary_city sale_price_ranges rental_price_ranges legal_name legal_document legal_address privacy_email creci
    institutional_mission institutional_vision institutional_values useful_links
  ].freeze

  attribute :primary_city, :string
  attribute :sale_price_ranges, :string
  attribute :rental_price_ranges, :string
  attribute :legal_name, :string
  attribute :legal_document, :string
  attribute :legal_address, :string
  attribute :privacy_email, :string
  attribute :creci, :string
  attribute :institutional_mission, :string
  attribute :institutional_vision, :string
  attribute :institutional_values, :string
  attribute :useful_links, :string

  attr_reader :tenant

  validates :privacy_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validate :validate_price_ranges
  validate :validate_useful_links

  def self.current(tenant: Current.tenant || Tenant.public_for)
    values = FIELDS.to_h { |field| [field, Setting.get("#{PREFIX}.#{field}", nil, tenant: tenant)] }

    new(values, tenant: tenant)
  end

  def initialize(attributes = {}, tenant:)
    @tenant = tenant || raise(ArgumentError, "Tenant obrigatório para perfil do site público")
    super(attributes)
  end

  def save
    return false unless valid?

    FIELDS.each do |field|
      Setting.set("#{PREFIX}.#{field}", public_send(field).to_s.strip, "Perfil público: #{field}", tenant: tenant)
    end
    true
  end

  def sale_price_options
    parsed_price_options(sale_price_ranges)
  end

  def rental_price_options
    parsed_price_options(rental_price_ranges)
  end

  def activation_gaps
    {
      "Cidade principal" => primary_city,
      "Razão social" => legal_name,
      "Documento da empresa" => legal_document,
      "Endereço jurídico" => legal_address,
      "E-mail de privacidade" => privacy_email,
      "CRECI" => creci
    }.filter_map { |label, value| label if value.blank? }
  end

  def useful_link_options
    useful_links.to_s.lines.filter_map do |line|
      label, url, description, icon = line.strip.split("|", 4).map(&:to_s)
      next if label.blank? || url.blank?

      { label: label, url: url, description: description, icon: icon.presence || "link-45deg" }
    end
  end

  private

  def parsed_price_options(raw)
    raw.to_s.lines.filter_map do |line|
      label, minimum, maximum = line.strip.split("|", 3).map(&:to_s)
      next if label.blank?

      range = [minimum.presence, maximum.presence].compact.join("-")
      [label, range]
    end
  end

  def validate_price_ranges
    %i[sale_price_ranges rental_price_ranges].each do |field|
      public_send(field).to_s.lines.each_with_index do |line, index|
        next if line.blank?
        parts = line.strip.split("|", -1)
        next if parts.size == 3 && parts.first.present? && parts.drop(1).all? { |value| value.blank? || value.match?(/\A\d+\z/) }

        errors.add(field, "linha #{index + 1} deve usar Nome|mínimo|máximo")
      end
    end
  end

  def validate_useful_links
    useful_links.to_s.lines.each_with_index do |line, index|
      next if line.blank?

      label, url, = line.strip.split("|", 4)
      valid_url = URI.parse(url.to_s).then { |uri| uri.is_a?(URI::HTTP) && uri.host.present? }
      next if label.present? && valid_url

      errors.add(:useful_links, "linha #{index + 1} deve usar Nome|https://endereço|Descrição|ícone")
    rescue URI::InvalidURIError
      errors.add(:useful_links, "linha #{index + 1} contém uma URL inválida")
    end
  end
end
