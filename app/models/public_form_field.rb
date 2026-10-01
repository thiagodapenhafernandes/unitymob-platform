class PublicFormField < ApplicationRecord
  include PublicSite::BumpsPageVersion
  FIELD_TYPES = %w[
    text email tel url search number currency date time datetime-local month week
    color range textarea select radio checkbox hidden file
  ].freeze

  FILE_KINDS = {
    "documents" => %w[pdf doc docx xls xlsx odt ods rtf txt csv],
    "images" => %w[jpg jpeg png webp heic]
  }.then { |kinds| kinds.merge("both" => kinds.values.flatten) }.freeze
  FILE_KIND_LABELS = {
    "documents" => "Documentos (PDF, Word, Excel…)",
    "images" => "Imagens",
    "both" => "Documentos e imagens"
  }.freeze
  FILE_MAX_MB_LIMIT = 25
  FILE_MAX_FILES = 5

  # Largura no modal: automática (tipos longos em linha inteira, o resto em meia coluna), meia ou inteira.
  WIDTHS = { "auto" => "Automática", "half" => "Meia (2 colunas)", "full" => "Inteira (1 coluna)" }.freeze
  FULL_WIDTH_TYPES = %w[textarea radio checkbox file].freeze

  # Máscara de digitação: 0 = dígito, A = letra, * = letra ou número; os demais símbolos são fixos.
  # "money" é o modo de dinheiro (R$ 1.234,56), que muda de tamanho.
  MASKABLE_TYPES = %w[text tel number currency].freeze
  MASK_FORMAT = /\A(?:money|[0A*\s\-.\/()+,:$%]{1,40})\z/
  MASK_PRESETS = {
    "Telefone (celular)" => "(00) 00000-0000", "Telefone (fixo)" => "(00) 0000-0000", "CRECI" => "00000-A",
    "CPF" => "000.000.000-00", "CNPJ" => "00.000.000/0000-00", "CEP" => "00000-000", "Dinheiro (R$)" => "money"
  }.freeze

  belongs_to :public_form, inverse_of: :fields

  validates :field_type, :name, :label, presence: true
  validates :field_type, inclusion: { in: FIELD_TYPES }
  validates :name, uniqueness: { scope: :public_form_id }, format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :options_required_for_choice_fields
  validate :mask_format_is_valid

  before_validation :normalize_name
  before_validation :parse_options_text
  before_validation :normalize_config

  attr_writer :options_text

  # Só no preview do builder: índice do campo em fields_attributes, para ligar o preview ao card do builder.
  attr_accessor :preview_key

  # Atribuição parcial (ex.: só width e mask) preserva o resto da config do campo.
  def config=(value)
    super(config.to_h.merge(value.to_h.stringify_keys))
  end

  def width_setting
    WIDTHS.key?(config.to_h["width"]) ? config["width"] : "auto"
  end

  def effective_width
    return width_setting unless width_setting == "auto"

    FULL_WIDTH_TYPES.include?(field_type) ? "full" : "half"
  end

  def maskable?
    MASKABLE_TYPES.include?(field_type)
  end

  # Máscara em vigor: a configurada ou, no tipo Moeda, o modo dinheiro.
  def mask_value
    return unless maskable?

    mask = config.to_h["mask"].to_s.strip
    mask = "money" if mask.blank? && field_type == "currency"
    mask if mask.match?(MASK_FORMAT)
  end

  def mask?
    mask_value.present?
  end

  def mask_hint
    mask_value == "money" ? "R$ 0,00" : mask_value
  end

  # Só dígitos e símbolos fixos (teclado numérico no celular).
  def mask_digits_only?
    mask_value == "money" || mask_value.to_s.delete("0").match?(/\A[\s\-.\/()+,:$%]*\z/)
  end

  # Regex equivalente à máscara, sem âncoras: serve ao atributo `pattern` do HTML e à validação no servidor.
  def mask_pattern_source
    mask = mask_value
    return unless mask
    return 'R\$ \d{1,3}(?:\.\d{3})*,\d{2}' if mask == "money"

    mask.each_char.map do |char|
      case char
      when "0" then '\d'
      when "A" then "[A-Za-z]"
      when "*" then "[A-Za-z0-9]"
      when %r{[\\^$.*+?()\[\]{}|/]} then "\\#{char}"
      else char
      end
    end.join
  end

  def mask_match?(value)
    source = mask_pattern_source
    source.nil? || value.to_s.match?(Regexp.new("\\A#{source}\\z"))
  end

  def choice_field?
    field_type.in?(%w[select radio checkbox])
  end

  def hidden?
    field_type == "hidden"
  end

  def file_field?
    field_type == "file"
  end

  def file_kind
    FILE_KINDS.key?(config.to_h["kind"]) ? config["kind"] : "both"
  end

  def file_extensions
    FILE_KINDS.fetch(file_kind)
  end

  def file_accept
    file_extensions.map { |extension| ".#{extension}" }.join(",")
  end

  def file_max_mb
    (config.to_h["max_mb"].to_i.nonzero? || 10).clamp(1, FILE_MAX_MB_LIMIT)
  end

  def file_multiple?
    config.to_h["multiple"].to_s.in?(%w[1 true])
  end

  def file_max_files
    file_multiple? ? FILE_MAX_FILES : 1
  end

  def file_summary
    "#{FILE_KIND_LABELS.fetch(file_kind)} · até #{file_max_mb} MB#{" por arquivo, máx. #{file_max_files}" if file_multiple?}"
  end

  def options_text
    return @options_text if defined?(@options_text)

    Array(options).map do |option|
      label = option.is_a?(Hash) ? option["label"] : option.to_s
      value = option.is_a?(Hash) ? option["value"] : option.to_s
      label == value ? label : "#{label}|#{value}"
    end.join("\n")
  end

  def normalized_options
    Array(options).filter_map do |option|
      next unless option.is_a?(Hash)

      label = option["label"].to_s.strip
      value = option["value"].to_s.strip.presence || label.parameterize
      next if label.blank?

      { "label" => label, "value" => value }
    end
  end

  private

  def normalize_config
    normalized = config.to_h
    normalized.delete("width") unless %w[half full].include?(normalized["width"])
    mask = normalized["mask"].to_s.strip
    if mask.blank? || !maskable?
      normalized.delete("mask")
    else
      normalized["mask"] = mask
    end
    self[:config] = normalized
  end

  def mask_format_is_valid
    mask = config.to_h["mask"].to_s.strip
    return if mask.blank? || !maskable? || mask.match?(MASK_FORMAT)

    errors.add(:mask, "use só 0 (dígito), A (letra), * (letra ou número) e símbolos como - . / ( ) espaço")
  end

  def normalize_name
    self.name = name.to_s.parameterize(separator: "_")
  end

  def parse_options_text
    return unless defined?(@options_text)

    self.options = @options_text.to_s.lines.filter_map do |line|
      raw = line.strip
      next if raw.blank?

      label, value = raw.split("|", 2).map { |part| part.to_s.strip }
      { "label" => label, "value" => value.presence || label.parameterize }
    end
  end

  def options_required_for_choice_fields
    return unless choice_field?
    return if normalized_options.any?

    errors.add(:options, "precisa ter ao menos uma opção")
  end

  private

  def public_page_version_tenant_id
    PublicForm.unscoped.where(id: public_form_id).pick(:tenant_id)
  end

end
