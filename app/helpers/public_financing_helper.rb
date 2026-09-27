# Simulador de financiamento do site público (ligado por conta em Perfil público).
module PublicFinancingHelper
  def public_financing_profile
    @public_financing_profile ||= @public_site_profile || PublicSiteProfile.current(tenant: public_tenant)
  end

  def public_financing_enabled?
    public_financing_profile.financing_simulator_enabled?
  end

  # Link do menu: nil some com o item quando a conta desliga o simulador.
  def public_financing_simulator_url
    simulador_path if public_financing_enabled?
  end

  def public_financing_rate
    @public_financing_rate ||= public_financing_profile.financing_rate
  end

  # Taxa para imóvel acima do teto do SFH (média de mercado ou a própria da conta).
  def public_financing_market_rate
    @public_financing_market_rate ||= public_financing_profile.financing_market_rate
  end

  def public_financing_rate_for(price_cents)
    price_cents.to_i > Financing::CentralBankRate::SFH_LIMIT_CENTS ? public_financing_market_rate : public_financing_rate
  end

  # Nota da taxa de mercado: explica por que o imóvel caro usa outra média.
  def public_financing_market_note
    note = public_financing_rate_note(public_financing_market_rate)
    return note if public_financing_market_rate.source == "custom"

    "#{note}. Imóveis acima de R$ 1,5 mi são financiados fora do SFH, com taxa de mercado"
  end

  # "11,30% a.a. — média do financiamento imobiliário (Banco Central, jul/2026)"
  def public_financing_rate_note(rate = public_financing_rate)
    value = "#{number_with_precision(rate.annual_rate, precision: 2, separator: ',')}% a.a."
    return "#{value} — taxa de referência da imobiliária" if rate.source == "custom"
    return "#{value} — taxa de referência (Banco Central indisponível no momento)" if rate.fallback

    series = Financing::CentralBankRate::SERIES.fetch(rate.source)[:label]
    month = rate.reference_date ? " #{I18n.l(rate.reference_date, format: '%b/%Y').downcase}" : ""
    "#{value} — #{series} (Banco Central#{month})"
  end

  # Parcela de chamada do botão no card de preço, com as premissas iniciais do
  # simulador (entrada 20%, 30 anos, taxa da conta, tabela Price — a menor
  # parcela inicial). Mesma fórmula do financing_simulator_controller.js.
  FINANCING_TEASER_DOWN = 0.2
  FINANCING_TEASER_MONTHS = 360

  def public_financing_teaser_payment(price_cents, rate = public_financing_rate_for(price_cents))
    financed = price_cents.to_i / 100.0 * (1 - FINANCING_TEASER_DOWN)
    return if financed <= 0

    monthly = ((1 + rate.annual_rate.to_f / 100)**(1.0 / 12)) - 1
    return financed / FINANCING_TEASER_MONTHS if monthly.zero?

    financed * monthly / (1 - ((1 + monthly)**-FINANCING_TEASER_MONTHS))
  end
end

