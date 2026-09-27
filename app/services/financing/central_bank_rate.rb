require "json"
require "net/http"

module Financing
  # Taxa média de financiamento imobiliário para pessoa física, publicada pelo
  # Banco Central (SGS, dados abertos, sem chave). É a média do mercado, não a
  # taxa de um banco: o simulador precisa dizer isso ao visitante.
  #
  #   Financing::CentralBankRate.fetch("bcb_total")
  #   # => #<Result annual_rate=11.3, reference_date=2026-07-01, source="bcb_total", fallback=false>
  #
  # O BC publica com ~2-3 meses de atraso (reference_date mostra o mês). Cache
  # de 12h; se a API falhar, usa o último valor bom (guardado por 30 dias) e,
  # sem ele, FALLBACK_RATE. Nunca levanta erro para a página.
  class CentralBankRate
    SERIES = {
      "bcb_total" => { code: 20774, label: "média do financiamento imobiliário" },
      "bcb_regulated" => { code: 20773, label: "média do financiamento com taxas reguladas (SFH)" },
      "bcb_market" => { code: 20772, label: "média do financiamento com taxas de mercado" }
    }.freeze
    DEFAULT_SOURCE = "bcb_total".freeze
    MARKET_SOURCE = "bcb_market".freeze
    # Teto de valor do imóvel no Sistema Financeiro da Habitação (CMN, desde
    # 2018). Acima dele o financiamento é com taxa de mercado. Revisar se o CMN
    # mudar o teto.
    SFH_LIMIT_CENTS = 1_500_000_00
    FALLBACK_RATE = 8.5
    TIMEOUT = 3

    Result = Data.define(:annual_rate, :reference_date, :source, :fallback) do
      def cache_key = [source, annual_rate, reference_date&.iso8601].join(":")
    end

    def self.fetch(source = DEFAULT_SOURCE)
      source = SERIES.key?(source.to_s) ? source.to_s : DEFAULT_SOURCE
      # Cache guarda hash simples (não o Data), para não depender de Marshal da classe.
      data = Rails.cache.fetch("financing/central_bank_rate/v1/#{source}", expires_in: 12.hours) do
        fresh = new(source).request&.to_h
        if fresh
          Rails.cache.write(last_good_key(source), fresh, expires_in: 30.days)
          fresh
        else
          Rails.cache.read(last_good_key(source)) || { annual_rate: FALLBACK_RATE, reference_date: nil, source:, fallback: true }
        end
      end
      Result.new(**data.symbolize_keys)
    end

    def self.last_good_key(source) = "financing/central_bank_rate/v1/last_good/#{source}"

    def initialize(source)
      @source = source
    end

    def request
      uri = URI("https://api.bcb.gov.br/dados/serie/bcdata.sgs.#{SERIES.fetch(@source)[:code]}/dados/ultimos/1?formato=json")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.get(uri.request_uri, "Accept" => "application/json")
      end
      return unless response.is_a?(Net::HTTPSuccess)

      row = JSON.parse(response.body).last
      rate = Float(row["valor"])
      return unless rate.positive? && rate < 100

      Result.new(annual_rate: rate, reference_date: Date.strptime(row["data"], "%d/%m/%Y"), source: @source, fallback: false)
    rescue StandardError => e
      Rails.logger.warn("[financing.central_bank_rate] source=#{@source} #{e.class}: #{e.message}")
      nil
    end
  end
end
