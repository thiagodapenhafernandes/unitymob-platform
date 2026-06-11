# frozen_string_literal: true

require "csv"

module Captacoes
  class SpreadsheetExporter
    HEADERS = [
      "Data",
      "Responsável Cadastro",
      "Empreendimento",
      "Nº Imóvel",
      "Cód. Imóvel CRM",
      "nome_proprietario",
      "telefone_proprietario",
      "email",
      "Cidade",
      "Time",
      "Corretor / Captador",
      "Região Foco Captação",
      "Valor de venda",
      "Valor de locação",
      "Administração",
      "Status",
      "Categoria"
    ].freeze

    def initialize(scope, helpers:)
      @scope = scope
      @helpers = helpers
    end

    def to_csv
      CSV.generate(headers: true, col_sep: ";") do |csv|
        csv << HEADERS
        scope.find_each(batch_size: 500) { |captacao| csv << row_for(captacao) }
      end
    end

    private

    attr_reader :scope, :helpers

    def row_for(captacao)
      [
        formatted_datetime(captacao.created_at),
        captacao.admin_user&.name,
        captacao.nome_empreendimento,
        captacao.unidade_numero,
        captacao.codigo,
        captacao.proprietario,
        captacao.proprietario_celular,
        captacao.proprietario_email,
        captacao.cidade,
        team_label(captacao),
        captacao.admin_user&.name.presence || captacao.corretor_nome,
        yes_no(focus_region?(captacao)),
        currency_from_cents(captacao.valor_venda_cents),
        currency_from_cents(captacao.valor_locacao_cents),
        administration_label(captacao),
        publication_status(captacao),
        captacao.categoria
      ]
    end

    def formatted_datetime(value)
      return if value.blank?

      I18n.l(value.in_time_zone, format: "%d/%m/%Y %H:%M")
    end

    def team_label(captacao)
      case captacao.modalidade
      when "venda" then "Time Venda"
      when "locacao_anual", "locacao_diaria" then "Time Locação"
      when "ambos" then "Time Venda/Locação"
      else captacao.status.to_s == "Aluguel" ? "Time Locação" : "Time Venda"
      end
    end

    def focus_region?(captacao)
      value = captacao.regiao_foco.to_s.strip
      value.present? && value != "." && !I18n.transliterate(value).match?(/\A(nao|sem preferencia)\z/i)
    end

    def yes_no(value)
      value ? "SIM" : "NÃO"
    end

    def currency_from_cents(value)
      cents = value.to_i
      return if cents <= 0

      helpers.number_to_currency(cents / 100.0, unit: "R$", format: "%u %n", separator: ",", delimiter: ".", precision: 2)
    end

    def administration_label(captacao)
      explicit = captacao.salute_rental_management_answer.to_s
      return "SIM" if explicit == "sim"
      return "NÃO" if explicit == "nao"

      yes_no(captacao.salute_rental_management_flag?)
    end

    def publication_status(captacao)
      photo_label = captacao.foto_classificacao.presence || "Não informado"

      if captacao.exibir_no_site_flag?
        "Publicado com #{photo_label.to_s.downcase}"
      else
        "Não foi publicado - #{photo_label}"
      end
    end
  end
end
