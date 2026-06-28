module Whatsapp
  class CampaignTemplatePreview
    SAMPLE_VALUES = {
      "nome" => "Maria Lead",
      "telefone" => "5547999990000",
      "email" => "maria@example.test",
      "origem" => "site",
      "status" => "Novo",
      "tags" => "Produto, Premium",
      "produto" => "Apartamento decorado",
      "empresa" => "Salute Imóveis",
      "observacoes" => "Contato pediu retorno no periodo da tarde",
      "corretor" => "Corretor Responsável",
      "corretor_telefone" => "5511999990000",
      "corretor_email" => "corretor@example.test"
    }.freeze

    Result = Struct.new(:body, :values, keyword_init: true)

    def self.call(template:, variables:)
      new(template, variables).call
    end

    def initialize(template, variables)
      @template = template
      @variables = variables.to_h
    end

    def call
      values = template_values
      Result.new(body: template.render_body(values), values: values)
    end

    private

    attr_reader :template, :variables

    def template_values
      count = template.variable_count
      return [] unless count.positive?

      Array(1..count).map do |index|
        render_variable(variables[index.to_s].presence || "{{#{index}}}")
      end
    end

    def render_variable(value)
      value.to_s.gsub(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/) do
        SAMPLE_VALUES[Regexp.last_match(1).to_s] || Regexp.last_match(0)
      end
    end
  end
end
