require "set"

module Admin
  class HabitationDevelopmentFilterOptions
    DEVELOPMENT_PREFIX = "dev:".freeze
    STANDALONE_PREFIX = "name:".freeze

    def self.call(scope)
      new(scope).call
    end

    def self.development_value(code)
      "#{DEVELOPMENT_PREFIX}#{code}"
    end

    def self.standalone_value(name)
      "#{STANDALONE_PREFIX}#{name}"
    end

    def self.parse(value)
      raw_value = value.to_s.strip
      return { type: :blank } if raw_value.blank?

      if raw_value.start_with?(DEVELOPMENT_PREFIX)
        return { type: :development, value: raw_value.delete_prefix(DEVELOPMENT_PREFIX).strip }
      end

      if raw_value.start_with?(STANDALONE_PREFIX)
        return { type: :standalone, value: raw_value.delete_prefix(STANDALONE_PREFIX).strip }
      end

      { type: :legacy, value: raw_value }
    end

    def initialize(scope)
      @scope = scope
    end

    def call
      developments = development_options
      names_with_development = developments.map { |name, _value| normalized_text(name) }.to_set
      standalone = standalone_options(names_with_development)

      (developments + standalone)
        .uniq { |name, _value| normalized_text(name) }
        .sort_by { |name, _value| normalized_text(name) }
    end

    private

    attr_reader :scope

    def development_options
      scope
        .empreendimentos
        .where("NULLIF(TRIM(codigo), '') IS NOT NULL")
        .where("NULLIF(TRIM(nome_empreendimento), '') IS NOT NULL AND nome_empreendimento != '.'")
        .pluck(:nome_empreendimento, :codigo)
        .map { |name, code| [name, self.class.development_value(code)] }
    end

    def standalone_options(names_with_development)
      scope
        .where("NULLIF(TRIM(nome_empreendimento), '') IS NOT NULL AND nome_empreendimento != '.'")
        .where.not(tipo: "Empreendimento")
        .pluck(:nome_empreendimento)
        .reject { |name| names_with_development.include?(normalized_text(name)) }
        .group_by { |name| normalized_text(name) }
        .values
        .map { |names| preferred_display_name(names) }
        .map { |name| [name, self.class.standalone_value(name)] }
    end

    def normalized_text(value)
      I18n.transliterate(value.to_s).squish.downcase
    end

    def preferred_display_name(names)
      names
        .compact_blank
        .map(&:to_s)
        .sort_by { |name| [name == name.downcase ? 1 : 0, name.length, name] }
        .first
    end
  end
end
