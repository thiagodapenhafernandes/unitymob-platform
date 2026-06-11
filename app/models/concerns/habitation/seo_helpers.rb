module Habitation::SeoHelpers
  extend ActiveSupport::Concern
  
  # Retorna o título SEO otimizado
  def seo_title
    if meta_title.present?
      meta_title
    else
      generate_seo_title
    end
  end
  
  # Retorna a descrição SEO otimizada
  def seo_description
    if meta_description.present?
      meta_description.to_plain_text
    else
      generate_seo_description
    end
  end
  
  # Retorna keywords SEO
  def seo_keywords
    if meta_keywords.present?
      meta_keywords
    else
      generate_seo_keywords
    end
  end
  
  # Retorna dados estruturados para Schema.org (JSON-LD)
  def structured_data
    {
      '@context': 'https://schema.org',
      '@type': 'RealEstateListing',
      name: display_title,
      description: seo_description,
      url: canonical_url,
      identifier: codigo,
      image: image_urls.presence || [primary_image_url].compact,
      address: address_structured_data,
      geo: geo_structured_data,
      floorSize: floor_size_data,
      numberOfRooms: dormitorios_qtd,
      numberOfBathroomsTotal: banheiros_qtd,
      petsAllowed: 'UnknownPermitType',
      offers: offer_structured_data
    }.compact
  end
  
  # URL canônica para SEO
  def canonical_url
    "#{ENV.fetch('APP_HOST', 'https://saluteimoveis.com')}/imovel/#{slug}"
  end
  
  # Open Graph tags
  def og_tags
    {
      'og:type' => 'product',
      'og:title' => seo_title,
      'og:description' => seo_description,
      'og:url' => canonical_url,
      'og:image' => primary_image_url,
      'og:site_name' => 'Salute Imóveis',
      'og:locale' => 'pt_BR'
    }.compact
  end
  
  # Twitter Card tags
  def twitter_tags
    {
      'twitter:card' => 'summary_large_image',
      'twitter:title' => seo_title,
      'twitter:description' => seo_description,
      'twitter:image' => primary_image_url
    }.compact
  end
  
  private
  
  def generate_seo_title
    # Templates variados baseados no perfil do imóvel
    templates = []
    
    # Identificar Power Features (Características de alto valor)
    power_features = []
    
    # Flags seguras via helper ou colunas explícitas conhecidas
    is_frente_mar = has_characteristic?('frente_mar') || has_characteristic?('vista_frente_mar')
    is_quadra_mar = has_characteristic?('quadra_mar')
    is_vista_mar = has_characteristic?('vista_mar')
    
    power_features << "Frente Mar" if is_frente_mar
    power_features << "Quadra Mar" if is_quadra_mar
    power_features << "Vista Mar" if is_vista_mar && !is_frente_mar
    power_features << "Mobiliado" if has_characteristic?('mobiliado')
    power_features << "Decorado" if has_characteristic?('decorado')
    power_features << "Com Piscina" if has_characteristic?('piscina')
    power_features << "Alto Padrão" if valor_venda_cents.to_i > 2_500_000
    power_features << "Oportunidade" if valor_venda_anterior_cents.to_i > valor_venda_cents.to_i
    
    # Identificar Estado (Status)
    status_imovel = []
    status_imovel << "Lançamento" if has_characteristic?('lancamento')
    status_imovel << "Na Planta" if has_characteristic?('na_planta')
    status_imovel << "Pronto para Morar" if has_characteristic?('pronto')
    status_imovel << "Novo" if created_at > 3.months.ago
    
    # Prefixo (Adjetivo de impacto)
    prefix = status_imovel.first || power_features.find { |f| ["Alto Padrão", "Oportunidade"].include?(f) }
    
    # Construção do Título
    parts = []
    
    # 1. O Que é?
    main_subject = categoria || "Imóvel"
    
    # 2. Onde?
    location_term = if bairro.present? && cidade.present?
                      "#{bairro}, #{cidade}"
                    elsif cidade.present?
                      cidade
                    else
                      "Balneário Camboriú"
                    end
    
    # Lógica de Templates Variados
    if prefix.present? && prefix != "Oportunidade"
       # Ex: Lançamento: Apartamento Frente Mar no Centro, BC
       feature = (power_features - [prefix]).first # Pega outra feature se disponível
       parts << "#{prefix}: #{main_subject}"
       parts << feature if feature
       parts << "em #{location_term}"
    elsif power_features.any?
       # Ex: Apartamento Frente Mar Mobiliado em BC
       parts << main_subject
       parts << power_features.first(2).join(' ') # Até 2 features
       parts << "em #{location_term}"
    else
       # Padrão
       parts << main_subject
       parts << "#{dormitorios_qtd} Quartos" if dormitorios_qtd.to_i > 0
       parts << "em #{location_term}"
    end
    
    # Sufixo de Preço ou Salute
    title = parts.join(' ')
    if title.length < 50
       title += " | Salute Imóveis"
    end
    
    title
  end
  
  def generate_seo_description
    # Copywriting Dinâmico
    
    # Features para narrative
    features_list = []
    features_list << "frente para o mar" if has_characteristic?('frente_mar')
    features_list << "totalmente mobiliado" if has_characteristic?('mobiliado')
    features_list << "finamente decorado" if has_characteristic?('decorado')
    features_list << "com ampla sacada com churrasqueira" if has_characteristic?('sacada') && has_characteristic?('churrasqueira')
    features_list << "com piscina privativa" if has_characteristic?('piscina')
    features_list << "com #{suites_qtd} suítes" if suites_qtd.to_i > 0
    features_list << "#{vagas_qtd} vagas de garagem" if vagas_qtd.to_i > 0
    
    # Location
    loc = bairro.present? ? "no bairro #{bairro}" : "em #{cidade}"
    
    # Templates de Introdução (Hooks)
    intros = []
    
    if has_characteristic?('lancamento')
      intros << "Conheça este lançamento exclusivo #{loc}."
      intros << "Invista no futuro com este empreendimento na planta #{loc}."
    elsif valor_venda_anterior_cents.to_i > valor_venda_cents.to_i
      intros << "Oportunidade Imperdível! Valor reduzido para este #{categoria&.downcase} #{loc}."
      intros << "Excelente negócio! #{categoria} com preço especial #{loc}."
    elsif valor_venda_cents.to_i > 3_000_000
      intros << "Viva o luxo e a sofisticação neste #{categoria&.downcase} de alto padrão #{loc}."
      intros << "Exclusividade define este imóvel #{loc}."
    else
      intros << "Encante-se com este #{categoria&.downcase} #{loc}."
      intros << "Seu novo lar espera por você #{loc}."
      intros << "Excelente opção de #{categoria&.downcase} para #{tipo_transacao&.downcase}."
    end
    
    # Selecionar intro baseada no ID para consistência (mas pseudo-randomica)
    intro = intros[id % intros.length]
    
    # Corpo
    body = "Este imóvel conta com #{features_list.to_sentence(last_word_connector: ' e ')}."
    
    # CTA
    ctas = [
      "Agende sua visita hoje mesmo e surpreenda-se!",
      "Entre em contato com a Salute Imóveis para mais detalhes.",
      "Não perca essa chance, fale conosco agora.",
      "Veja mais fotos e informações exclusivas."
    ]
    cta = ctas[(id + 1) % ctas.length]
    
    "#{intro} #{body} #{cta}"
  end
  
  # Helper para verificar características no JSONB ou Flags
  def has_characteristic?(term)
    # Verifica nas flags explícitas se existirem (metaprogramação segura ou check manual)
    return true if respond_to?("#{term}_flag") && send("#{term}_flag")
    
    # Verifica no JSONB de características
    return true if caracteristicas.is_a?(Hash) && 
                   caracteristicas.keys.any? { |k| k.to_s.parameterize.include?(term.parameterize) } ||
                   caracteristicas.is_a?(Hash) && caracteristicas[term.to_s] == true
                   
    # Verifica em infraestrutura array
    return true if infra_estrutura.is_a?(Array) && 
                   infra_estrutura.any? { |i| i.to_s.parameterize.include?(term.parameterize) }
                   
    # Verifica strings especiais
    return true if term == 'frente_mar' && (respond_to?(:frente_mar_avenida_atlantica_flag) && frente_mar_avenida_atlantica_flag)
    
    false
  end
  
  def generate_seo_keywords
    keywords = []
    
    # Categoria e tipo
    keywords << categoria if categoria.present?
    keywords << tipo_transacao if tipo_transacao.present?
    
    # Localização
    keywords << cidade if cidade.present?
    keywords << bairro if bairro.present?
    keywords << uf if uf.present?
    
    # Características
    keywords << "#{dormitorios_qtd} dormitórios" if dormitorios_qtd.to_i > 0
    keywords << "#{suites_qtd} suítes" if suites_qtd.to_i > 0
    keywords << "#{vagas_qtd} vagas" if vagas_qtd.to_i > 0
    
    # Marca
    keywords << "Salute Imóveis"
    keywords << "Imobiliária"
    
    keywords.join(', ')
  end
  
  def address_structured_data
    return nil unless cidade.present?
    
    {
      '@type': 'PostalAddress',
      streetAddress: [tipo_endereco, endereco, numero].compact.join(' '),
      addressLocality: bairro,
      addressRegion: cidade,
      addressCountry: 'BR',
      postalCode: cep
    }.compact
  end
  
  def geo_structured_data
    return nil unless latitude.present? && longitude.present?
    
    {
      '@type': 'GeoCoordinates',
      latitude: latitude.to_f,
      longitude: longitude.to_f
    }
  end
  
  def floor_size_data
    return nil unless area_total_m2.present?
    
    {
      '@type': 'QuantitativeValue',
      value: area_total_m2.to_f,
      unitCode: 'MTK' # Square Meter
    }
  end
  
  def offer_structured_data
    price_cents = status&.downcase&.include?('venda') ? valor_venda_cents : valor_locacao_cents
    return nil unless price_cents.to_i > 0
    
    {
      '@type': 'Offer',
      price: (price_cents.to_f / 100.0).round(2),
      priceCurrency: 'BRL',
      availability: 'https://schema.org/InStock',
      url: canonical_url
    }
  end
end
