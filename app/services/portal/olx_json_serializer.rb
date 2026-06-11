module Portal
  class OlxJsonSerializer
    CONTACT = {
      name: "SALUTE IMOVEIS",
      email: "contato@saluteimoveis.com.br",
      phone: "(47) 3311-1067"
    }.freeze

    def initialize(habitations:, integration:, portal:)
      @habitations = habitations
      @integration = integration
      @portal = portal
    end

    def as_json
      {
        portal: @portal,
        generated_at: Time.current.iso8601,
        account_id: @integration.account_id,
        publisher_id: @integration.publisher_id,
        contact: CONTACT,
        listings: @habitations.map { |habitation| serialize_listing(habitation) }
      }
    end

    private

    def serialize_listing(habitation)
      {
        code: habitation.codigo,
        external_id: habitation.codigo,
        title: habitation.titulo_anuncio.presence || "Imóvel #{habitation.codigo}",
        description: description_for(habitation),
        status: habitation.status,
        property_type: property_type_for(habitation),
        category: habitation.categoria,
        business_types: business_types(habitation),
        sale_price_cents: habitation.valor_venda_cents.to_i,
        rent_price_cents: habitation.valor_locacao_cents.to_i,
        condominium_fee_cents: habitation.valor_condominio_cents.to_i,
        iptu_cents: habitation.valor_iptu_cents.to_i,
        bedrooms: habitation.dormitorios_qtd.to_i,
        suites: habitation.suites_qtd.to_i,
        bathrooms: habitation.banheiros_qtd.to_i,
        garage_spaces: habitation.vagas_qtd.to_i,
        useful_area_m2: numeric(habitation.area_privativa_m2),
        total_area_m2: numeric(habitation.area_total_m2),
        address: address_for(habitation),
        contact: CONTACT,
        features: features_for(habitation),
        publication_options: publication_options_for(habitation),
        exhibit_on_site: habitation.exibir_no_site_flag,
        images: image_objects(habitation)
      }
    rescue StandardError => e
      Rails.logger.error("[OlxJsonSerializer] habitation=#{habitation&.codigo} erro=#{e.message}")
      {
        code: habitation.codigo,
        title: habitation.titulo_anuncio.presence || "Imóvel #{habitation.codigo}",
        error: "Falha ao serializar"
      }
    end

    def description_for(habitation)
      habitation.descricao_web.to_plain_text.presence ||
        habitation.meta_description.to_plain_text.presence ||
        "Sem descrição"
    rescue
      "Sem descrição"
    end

    def address_for(habitation)
      address = habitation.address
      {
        street: habitation.endereco.presence || address&.logradouro,
        number: habitation.numero.presence || address&.numero,
        complement: habitation.complemento.presence || address&.complemento,
        neighborhood: habitation.bairro.presence || address&.bairro,
        city: habitation.cidade.presence || address&.cidade,
        state: habitation.uf.presence || address&.uf,
        zipcode: sanitize_cep(habitation.cep.presence || address&.cep),
        latitude: numeric(address&.latitude),
        longitude: numeric(address&.longitude)
      }
    end

    def business_types(habitation)
      types = []
      types << "venda" if habitation.valor_venda_cents.to_i.positive?
      types << "aluguel" if habitation.valor_locacao_cents.to_i.positive?
      types
    end

    def property_type_for(habitation)
      category = habitation.categoria.to_s.downcase
      case category
      when /cobertura/ then "cobertura"
      when /flat/ then "flat"
      when /loft/ then "loft"
      when /kitnet|studio/ then "kitnet"
      when /sobrado/ then "sobrado"
      when /casa em condom/ then "casa_em_condominio"
      when /casa comercial/ then "comercial"
      when /casa/ then "casa"
      when /apartamento/ then "apartamento"
      when /condomínio industrial|condominio industrial/ then "galpao"
      when /condomínio|condominio/ then "condominio"
      when /chácara|chacara|sítio|sitio/ then "rural"
      when /terreno|área|area/ then "terreno"
      when /galpão|galpao/ then "galpao"
      when /sala|conjunto/ then "comercial"
      when /loja|ponto comercial|prédio comercial|predio comercial/ then "comercial"
      when /empreendimento/ then "empreendimento"
      else "outros"
      end
    end

    def features_for(habitation)
      values = []
      values.concat(Array(habitation.infra_estrutura))
      values.concat(Array(habitation.caracteristicas&.values)) if habitation.caracteristicas.respond_to?(:values)
      values.concat(Array(habitation.unique_features)) if habitation.respond_to?(:unique_features)

      values.map { |value| value.to_s.strip }.reject(&:blank?).uniq.first(40)
    end

    def publication_options_for(habitation)
      opts = {}
      case @portal
      when "imovelweb"
        opts[:tipo_publicacao] = habitation.tipo_publicacao_imovelweb if habitation.respond_to?(:tipo_publicacao_imovelweb)
        opts[:mostrar_mapa] = habitation.mostrar_mapa_imovelweb if habitation.respond_to?(:mostrar_mapa_imovelweb)
      when "imovelweb_2"
        opts[:tipo_publicacao] = habitation.tipo_publicacao_imovelweb_2 if habitation.respond_to?(:tipo_publicacao_imovelweb_2)
        opts[:mostrar_mapa] = habitation.mostrar_mapa_imovelweb_2 if habitation.respond_to?(:mostrar_mapa_imovelweb_2)
      end
      opts.compact
    end

    def image_objects(habitation)
      habitation.image_urls.first(20).each_with_index.map do |url, idx|
        { url: url, primary: idx.zero?, position: idx + 1 }
      end
    end

    def sanitize_cep(cep)
      cep.to_s.gsub(/\D/, "").presence
    end

    def numeric(value)
      return nil if value.nil?
      number = value.to_f
      return nil if number.zero? && value.to_s.strip.empty?
      number
    end
  end
end
