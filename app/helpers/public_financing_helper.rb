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

  # "11,30% a.a. — média do financiamento imobiliário (Banco Central, jul/2026)"
  def public_financing_rate_note(rate = public_financing_rate)
    value = "#{number_with_precision(rate.annual_rate, precision: 2, separator: ',')}% a.a."
    return "#{value} — taxa de referência da imobiliária" if rate.source == "custom"
    return "#{value} — taxa de referência (Banco Central indisponível no momento)" if rate.fallback

    series = Financing::CentralBankRate::SERIES.fetch(rate.source)[:label]
    month = rate.reference_date ? " #{I18n.l(rate.reference_date, format: '%b/%Y').downcase}" : ""
    "#{value} — #{series} (Banco Central#{month})"
  end
end
