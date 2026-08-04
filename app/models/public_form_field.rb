class PublicFormField < ApplicationRecord
  FIELD_TYPES = %w[
    text email tel url search number currency date time datetime-local month week
    color range textarea select radio checkbox hidden
  ].freeze

  belongs_to :public_form, inverse_of: :fields

  validates :field_type, :name, :label, presence: true
  validates :field_type, inclusion: { in: FIELD_TYPES }
  validates :name, uniqueness: { scope: :public_form_id }, format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :options_required_for_choice_fields

  before_validation :normalize_name
  before_validation :parse_options_text

  attr_writer :options_text

  def choice_field?
    field_type.in?(%w[select radio checkbox])
  end

  def hidden?
    field_type == "hidden"
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
end
