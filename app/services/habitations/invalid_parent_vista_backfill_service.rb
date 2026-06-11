# frozen_string_literal: true

require "json"
require "rest-client"
require "uri"

module Habitations
  class InvalidParentVistaBackfillService
    VISTA_KEY = ENV.fetch("VISTA_KEY") { "ea83a702a7669520304be011258289fd" }
    VISTA_HOST = ENV.fetch("VISTA_HOST") { "http://saluteim20174-rest.vistahost.com.br" }
    DETALHES_PATH = "/imoveis/detalhes"

    Result = Struct.new(
      :invalid_parent_codes_total,
      :processed_codes,
      :fetched_from_vista,
      :created_or_updated_developments,
      :not_found_in_vista,
      :errors,
      :reconciliation_result,
      keyword_init: true
    )

    def initialize(apply: false, limit: nil)
      @apply = apply
      @limit = limit&.to_i
      @not_found = []
      @errors = []
      @processed = 0
      @fetched = 0
      @upserted = 0
    end

    def call
      parent_codes = invalid_parent_codes
      parent_codes = parent_codes.first(@limit) if @limit.present? && @limit.positive?

      if @apply
        parent_codes.each { |code| process_code!(code) }
        Habitations::HierarchyNormalizerService.new.call
      else
        parent_codes.each { |code| process_code(code) }
      end

      reconciliation_result =
        if @apply
          Habitations::InvalidParentReconciliationService.new(apply: true).call
        else
          Habitations::InvalidParentReconciliationService.new(apply: false).call
        end

      Result.new(
        invalid_parent_codes_total: invalid_parent_codes.size,
        processed_codes: @processed,
        fetched_from_vista: @fetched,
        created_or_updated_developments: @upserted,
        not_found_in_vista: @not_found,
        errors: @errors,
        reconciliation_result: reconciliation_result
      )
    end

    private

    def invalid_parent_codes
      @invalid_parent_codes ||= begin
        valid_development_codes = Habitation.empreendimentos.where.not(codigo: [nil, ""]).pluck(:codigo).map(&:to_s).to_set

        Habitation.where.not(codigo_empreendimento: [nil, ""])
                  .distinct
                  .pluck(:codigo_empreendimento)
                  .map(&:to_s)
                  .reject { |code| valid_development_codes.include?(code) }
      end
    end

    def process_code(code)
      @processed += 1
      details = fetch_details(code)
      if details.blank?
        @not_found << code
        return
      end

      @fetched += 1
    rescue StandardError => e
      @errors << { code: code, error: "#{e.class}: #{e.message}" }
    end

    def process_code!(code)
      @processed += 1
      details = fetch_details(code)
      if details.blank?
        @not_found << code
        return
      end

      @fetched += 1
      upsert_development_from_vista!(details)
      @upserted += 1
    rescue StandardError => e
      @errors << { code: code, error: "#{e.class}: #{e.message}" }
    end

    def fetch_details(code)
      payload = {
        fields: [
          "Codigo", "Empreendimento", "Categoria", "Status", "Situacao",
          "Construtora", "DataAtualizacao", "DataCadastro",
          "TipoEndereco", "Endereco", "Numero", "Complemento",
          "Bairro", "BairroComercial", "Cidade", "UF", "CEP", "Pais",
          "Latitude", "Longitude", "Imediacoes"
        ]
      }

      response = RestClient.get(
        "#{VISTA_HOST}#{DETALHES_PATH}",
        params: {
          key: VISTA_KEY,
          imovel: code,
          showSuspended: 1,
          pesquisa: payload.to_json
        },
        accept: :json
      )

      data = JSON.parse(response.body)
      return nil if data.blank? || data["Codigo"].blank?

      data
    rescue RestClient::ExceptionWithResponse
      nil
    end

    def upsert_development_from_vista!(hb)
      code = hb["Codigo"].to_s
      development = Habitation.find_or_initialize_by(codigo: code)

      constructor_name = hb["Construtora"].to_s.strip
      constructor_id = resolve_constructor_id(constructor_name)
      name = hb["Empreendimento"].to_s.strip
      category = hb["Categoria"].to_s.strip

      development.assign_attributes(
        slug: build_slug(hb),
        codigo: code,
        tipo: "Empreendimento",
        categoria: category.presence || "Empreendimento",
        status: hb["Status"].to_s.strip.presence || development.status,
        situacao: hb["Situacao"].to_s.strip.presence || development.situacao,
        nome_empreendimento: name.presence || development.nome_empreendimento || "Empreendimento #{code}",
        titulo_anuncio: development.titulo_anuncio.presence || name.presence || "Empreendimento #{code}",
        constructor_id: constructor_id.presence || development.constructor_id,
        construtora: constructor_name.presence || development.construtora,
        codigo_empreendimento: nil,
        endereco: hb["Endereco"],
        numero: hb["Numero"],
        complemento: hb["Complemento"],
        bairro: hb["Bairro"],
        bairro_comercial: hb["BairroComercial"],
        cidade: hb["Cidade"],
        uf: hb["UF"],
        cep: hb["CEP"],
        pais: hb["Pais"].presence || "Brasil",
        latitude: hb["Latitude"],
        longitude: hb["Longitude"],
        imediacoes: normalize_imediacoes(hb["Imediacoes"]).join(", "),
        data_atualizacao_crm: safe_parse_time(hb["DataAtualizacao"]) || Time.current,
        data_cadastro_crm: safe_parse_time(hb["DataCadastro"])
      )
      development.save!(validate: false)

      address = development.address || development.build_address
      address.assign_attributes(
        tipo_endereco: hb["TipoEndereco"],
        logradouro: hb["Endereco"],
        numero: hb["Numero"],
        complemento: hb["Complemento"],
        bairro: hb["Bairro"],
        bairro_comercial: hb["BairroComercial"],
        cidade: hb["Cidade"],
        uf: hb["UF"],
        cep: hb["CEP"],
        pais: hb["Pais"].presence || "Brasil",
        latitude: hb["Latitude"],
        longitude: hb["Longitude"],
        imediacoes: normalize_imediacoes(hb["Imediacoes"])
      )
      address.save!(validate: false)
    end

    def resolve_constructor_id(name)
      return nil if name.blank?

      normalized = name.strip
      constructor = Constructor.where("lower(name) = lower(?)", normalized).first
      constructor ||= Constructor.create!(name: normalized)
      constructor.id
    rescue StandardError
      nil
    end

    def normalize_imediacoes(raw_value)
      case raw_value
      when Array
        raw_value
      when String
        raw_value.split(/[,\n;]+/)
      else
        Array(raw_value)
      end.map { |item| item.to_s.strip }.reject(&:blank?).uniq
    end

    def safe_parse_time(value)
      return nil if value.blank?
      Time.zone.parse(value.to_s)
    rescue StandardError
      nil
    end

    def build_slug(hb)
      parts = [hb["Categoria"], hb["Cidade"], hb["Bairro"], hb["Codigo"]].compact
      parts.join("-").parameterize
    end
  end
end
