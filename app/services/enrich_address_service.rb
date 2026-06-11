require "net/http"
require "json"
require "uri"

class EnrichAddressService
  API_BASE_URL = "https://viacep.com.br/ws".freeze

  def initialize(cep:, fallback: {})
    @cep = cep
    @fallback = fallback.with_indifferent_access
  end

  def call
    api_data = fetch_viacep
    return fallback_data unless api_data

    type, street_name = extract_street_source(api_data["logradouro"])

    {
      tipo_endereco: type,
      logradouro: street_name,
      bairro: api_data["bairro"].presence || @fallback[:bairro],
      cidade: api_data["localidade"].presence || @fallback[:cidade],
      uf: api_data["uf"].presence || @fallback[:uf]
    }
  end

  private

  def fetch_viacep
    return nil if @cep.blank?

    clean_cep = @cep.gsub(/\D/, "")
    return nil unless clean_cep.length == 8

    uri = URI("#{API_BASE_URL}/#{clean_cep}/json/")
    response = Net::HTTP.get_response(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    data["erro"] ? nil : data
  rescue StandardError
    nil
  end

  def extract_street_source(logradouro)
    return ["Rua", logradouro] if logradouro.blank?

    match = Habitation::STREET_TYPES.find { |type| logradouro.match?(/^#{Regexp.escape(type)}\b/i) }
    return ["Rua", logradouro] unless match

    [match, logradouro.sub(/^#{Regexp.escape(match)}\s*/i, "").strip]
  end

  def fallback_data
    type, street_name = extract_street_source(@fallback[:logradouro])

    tipo_endereco = @fallback[:tipo_endereco].presence
    tipo_endereco = type unless tipo_endereco && Habitation::STREET_TYPES.include?(tipo_endereco)

    {
      tipo_endereco: tipo_endereco,
      logradouro: tipo_endereco == @fallback[:tipo_endereco] ? @fallback[:logradouro] : street_name,
      bairro: @fallback[:bairro],
      cidade: @fallback[:cidade],
      uf: @fallback[:uf]
    }
  end
end
