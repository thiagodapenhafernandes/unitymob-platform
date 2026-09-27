class PublicSiteProfile
  include ActiveModel::Model
  include ActiveModel::Attributes

  PREFIX = "public_site.profile".freeze
  FIELDS = %i[
    primary_city sale_price_ranges rental_price_ranges legal_name legal_document legal_address privacy_email creci
    institutional_mission institutional_vision institutional_values useful_links
    show_development_identity custom_price_ranges
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
  # Página da unidade revela o empreendimento (nome, rua, descrição, link)?
  # Desligado por padrão: o bloco do empreendimento fica discreto.
  attribute :show_development_identity, :boolean, default: false
  # Faixas da busca: nil/false = automáticas pelo estoque (PublicSite::PriceRanges);
  # true = usa as faixas digitadas. Contas antigas com faixas e sem a opção
  # gravada continuam personalizadas (custom_price_ranges?).
  attribute :custom_price_ranges, :boolean

  attr_reader :tenant

  validates :privacy_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validate :validate_price_ranges
  validate :validate_useful_links

  def self.current(tenant: Current.tenant || Tenant.public_for)
    values = FIELDS.to_h { |field| [field, Setting.tenant_get("#{PREFIX}.#{field}", nil, tenant: tenant)] }

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

  def show_development_identity?
    show_development_identity == true
  end

  def custom_price_ranges?
    return custom_price_ranges unless custom_price_ranges.nil?

    sale_price_ranges.present? || rental_price_ranges.present?
  end

  # Linhas estruturadas das telas do admin, gravadas no mesmo texto de sempre
  # (Nome|mínimo|máximo e Nome|URL|Descrição|ícone) — nada muda para quem lê.
  def sale_price_rows = price_rows_from(sale_price_ranges)
  def rental_price_rows = price_rows_from(rental_price_ranges)
  def sale_price_rows=(rows)
    self.sale_price_ranges = price_rows_to_text(rows)
  end

  def rental_price_rows=(rows)
    self.rental_price_ranges = price_rows_to_text(rows)
  end

  def useful_link_rows
    useful_links.to_s.lines.filter_map do |line|
      next if line.blank?

      label, url, description, icon = line.strip.split("|", 4).map(&:to_s)
      { label: label, url: url, description: description, icon: icon }
    end
  end

  def useful_link_rows=(rows)
    self.useful_links = present_rows(rows).map do |row|
      %i[label url description icon].map { |key| row[key].to_s.squish.delete("|") }.join("|").sub(/\|+\z/, "")
    end.join("\n")
  end

  def sale_price_options
    parsed_price_options(sale_price_ranges)
  end

  def rental_price_options
    parsed_price_options(rental_price_ranges)
  end

  # Prévia da tela do admin: como o filtro do site vai listar as faixas (mesma
  # regra de parsed_price_options) e quais linhas a validação vai recusar.
  def price_range_preview(field)
    raw = public_send(field)
    { options: parsed_price_options(raw), invalid_lines: invalid_price_range_lines(raw) }
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

  def present_rows(rows)
    list = rows.respond_to?(:to_unsafe_h) ? rows.to_unsafe_h : rows
    list = list.values if list.is_a?(Hash)
    Array(list).map { |row| row.to_h.symbolize_keys }.reject { |row| row.values.all?(&:blank?) }
  end

  def price_rows_from(raw)
    raw.to_s.lines.filter_map do |line|
      next if line.blank?

      label, minimum, maximum = line.strip.split("|", 3).map(&:to_s)
      { label: label, min: minimum, max: maximum }
    end
  end

  # Valores em reais; aceita "1.500.000". Nome vazio vira rótulo automático.
  def price_rows_to_text(rows)
    present_rows(rows).map do |row|
      minimum = row[:min].to_s.gsub(/\D/, "")
      maximum = row[:max].to_s.gsub(/\D/, "")
      label = row[:label].to_s.squish.delete("|").presence || PublicSite::PriceRanges.label_for(minimum, maximum)
      [label, minimum, maximum].join("|")
    end.join("\n")
  end

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
      invalid_price_range_lines(public_send(field)).each do |line_number|
        errors.add(field, "linha #{line_number} deve usar Nome|mínimo|máximo")
      end
    end
  end

  def invalid_price_range_lines(raw)
    raw.to_s.lines.each_with_index.filter_map do |line, index|
      next if line.blank?

      parts = line.strip.split("|", -1)
      next if parts.size == 3 && parts.first.present? && parts.drop(1).all? { |value| value.blank? || value.match?(/\A\d+\z/) }

      index + 1
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
