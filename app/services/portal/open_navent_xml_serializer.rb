require "builder"
require "set"
require "uri"

module Portal
  # Layout recuperado do gerador Vista/Imovelweb do projeto Salute (f64577a0).
  class OpenNaventXmlSerializer
    DEFAULT_PUBLICATION_TYPE = "SIMPLE".freeze
    DEFAULT_MAP_VISIBILITY = "APROXIMADO".freeze
    DEFAULT_MEDIA_UNIT = "M2".freeze

    CHARACTERISTICS = [
      ["30001", "ANDARES", :andares_qtd],
      ["20011", "AQUECIMENTO_CENTRAL", "Aquecimento central"],
      ["20012", "AR_CONDICIONADO", "Ar-condicionado"],
      ["CFT100", "AREA_TOTAL", :area_total_m2],
      ["CON1", "MEDIDAS", :measurement_unit],
      ["10027", "BICICLETARIO", "Bicicletário"],
      ["10028", "BRINQUEDOTECA", "Brinquedoteca"],
      ["20048", "CHURRASQUEIRA", "Churrasqueira"],
      ["10048", "CHURRASQUEIRA_Cond", "Churrasqueira"],
      ["20050", "CLOSET", "Closet"],
      ["20056", "COZINHA_AMERICANA", "Cozinha americana"],
      ["20065", "DESPENS", "Despensa"],
      ["10071", "ELEVADOR", :elevadores_qtd],
      ["20077", "ESCRITORIO", "Escritório"],
      ["10084", "ESTACIONAMENTO_PARA_VISITANTES", "Estacionamento para visitantes"],
      ["20088", "ESTUDA_PERMUTA", :aceita_permuta_flag],
      ["10090", "FITNESS/SALA_DE_GINASTICA", "Academia"],
      ["CFT7", "GARAGE", :vagas_qtd],
      ["10103", "GUARITA", "Guarita"],
      ["20106", "HIDROMASSAGEM", "Hidromassagem"],
      ["CFT400", "IPTU", :valor_iptu_cents],
      ["20114", "LAREIRA", "Lareira"],
      ["20117", "LAVANDERIA", "Lavanderia"],
      ["20124", "MEZANINO", "Mezanino"],
      ["20126", "MOBILIADO", :mobiliado],
      ["20140", "PISCINA", "Piscina"],
      ["10140", "PISCINA", "Piscina"],
      ["20152", "PLAYGROUND", "Playground"],
      ["10152", "PLAYGROUND", "Playground"],
      ["10158", "PORTARIA_24_HORAS", "Portaria 24 horas"],
      ["10165", "QUADRA_POLIESPORTIVA", "Quadra poliesportiva"],
      ["CFT2", "QUARTO", :dormitorios_qtd],
      ["20177", "SALA_DE_JANTAR", "Sala de jantar"],
      ["10183", "SAUNA", "Sauna"],
      ["20184", "SISTEMA_DE_ALARME", "Alarme"],
      ["CFT4", "SUITE", :suites_qtd],
      ["20199", "VARANDA", "Sacada"]
    ].freeze

    def initialize(habitations:, integration:)
      @habitations = habitations
      @integration = integration
      @identity = Tenants::PublicIdentity.new(integration.tenant)
    end

    def to_xml(target: nil)
      xml = Builder::XmlMarkup.new(**(target ? { target: target } : {}))
      xml.instruct! :xml, version: "1.0", encoding: "UTF-8"

      xml.OpenNavent do
        xml.dataModificacao Time.current.strftime("%Y%m%d%H%M%S")
        xml.Imoveis do
          @habitations.each do |habitation|
            xml.Imovel do
              add_publisher!(xml)
              xml.codigoAnuncio { xml.cdata!(habitation.codigo.to_s) }
              xml.codigoReferencia { xml.cdata!(habitation.codigo.to_s) }
              add_property_type!(xml, habitation)
              add_characteristics!(xml, habitation)
              xml.descricao description_for(habitation)
              add_location!(xml, habitation)
              add_prices!(xml, habitation)
              add_publication!(xml, habitation)
              xml.titulo { xml.cdata!(habitation.titulo_anuncio.presence || "Imóvel #{habitation.codigo}") }
              add_tours!(xml, habitation)
              add_media!(xml, habitation)
            end
          end
        end
      end

      target ? nil : xml.target!
    end

    private

    def add_publisher!(xml)
      xml.publicador do
        xml.codigoImobiliaria { xml.cdata!(publisher_code) }
        xml.emailUsuario { xml.cdata!(@identity.email.to_s) }
      end
    end

    def publisher_code
      @integration.account_id.presence || @integration.publisher_id.presence || ""
    end

    def add_property_type!(xml, habitation)
      id_tipo, id_subtipo, tipo = property_type_for(habitation)
      xml.tipoPropriedade do
        xml.idTipo { xml.cdata!(id_tipo) }
        xml.idSubTipo { xml.cdata!(id_subtipo) }
        xml.tipo { xml.cdata!(tipo) }
      end
    end

    def property_type_for(habitation)
      category = normalized_category(habitation.categoria)

      return ["2", "26", "Apartamento"] if category.include?("cobertura")
      return ["2", "3", "Apartamento"] if category.include?("loft")
      return ["2", "2", "Apartamento"] if category.match?(/kitnet|studio/)
      return ["2", "4", "Apartamento"] if category.include?("flat")
      return ["2", "1", "Apartamento"] if category.include?("apartamento")
      return ["1", "6", "Casa"] if category.include?("casa-em-condominio")
      return ["1005", "17", "Comercial"] if category.include?("casa-comercial")
      return ["1", "33", "Casa"] if category.include?("sobrado")
      return ["1", "5", "Casa"] if category.include?("casa")
      return ["1003", "9", "Terreno"] if category.include?("terreno-em-condominio")
      return ["1003", "8", "Terreno"] if category.match?(/terreno|\Aarea\z/)
      return ["1004", "10", "Rural"] if category.include?("chacara")
      return ["1004", "11", "Rural"] if category.include?("sitio")
      return ["1005", "20", "Comercial"] if category.match?(/galpao|industrial/)
      return ["1005", "15", "Comercial"] if category.include?("predio-comercial")
      return ["1005", "16", "Comercial"] if category.match?(/sala|conjunto/)
      return ["1005", "19", "Comercial"] if category.match?(/loja|ponto-comercial/)
      return ["1005", "16", "Comercial"] if category.include?("comercial")

      ["2", "1", "Apartamento"]
    end

    def add_characteristics!(xml, habitation)
      feature_index = feature_index_for(habitation)

      xml.caracteristicas do
        CHARACTERISTICS.each do |id, name, source|
          xml.caracteristica do
            xml.id { xml.cdata!(id) }
            xml.nome { xml.cdata!(name) }

            if source == :measurement_unit
              xml.idValor { xml.cdata!(DEFAULT_MEDIA_UNIT) }
            else
              xml.valor { xml.cdata!(characteristic_value(habitation, source, feature_index).to_s) }
            end
          end
        end
      end
    end

    def characteristic_value(habitation, source, feature_index)
      case source
      when :area_total_m2
        integer_or_zero(habitation.area_total_m2)
      when :valor_iptu_cents
        cents_to_units(habitation.valor_iptu_cents)
      when :mobiliado
        habitation.mobiliado_flag? || feature_index.include?("mobiliado") ? 1 : 0
      when Symbol
        value = habitation.public_send(source) if habitation.respond_to?(source)
        if value == true || value == false
          value ? 1 : 0
        else
          integer_or_zero(value)
        end
      else
        feature_index.include?(normalized_feature(source)) ? 1 : 0
      end
    end

    def feature_index_for(habitation)
      values = []
      values.concat(Array(habitation.infra_estrutura))
      values.concat(Array(habitation.caracteristicas))
      values.concat(Array(habitation.caracteristicas&.values)) if habitation.caracteristicas.respond_to?(:values)
      values.concat(Array(habitation.unique_features)) if habitation.respond_to?(:unique_features)
      values.map { |value| normalized_feature(value) }.reject(&:blank?).to_set
    end

    def add_location!(xml, habitation)
      xml.localizacao do
        xml.localidade location_text_for(habitation)
        xml.codigoPostal sanitize_cep(habitation.cep)
        xml.endereco habitation.endereco.to_s

        if (lat = coordinate(habitation, :latitude))
          xml.latitude lat
        end

        if (lng = coordinate(habitation, :longitude))
          xml.longitude lng
        end

        xml.mostrarMapa map_visibility_for(habitation)
      end
    end

    def location_text_for(habitation)
      [habitation.bairro, habitation.cidade, state_name_for(habitation.uf), "Brasil"].map(&:presence).compact.join(", ")
    end

    def add_prices!(xml, habitation)
      operation, amount = operation_and_amount_for(habitation)

      xml.precos do
        xml.preco do
          xml.operacao { xml.cdata!(operation) }
          xml.quantidade { xml.cdata!(amount.to_s) }
          xml.moeda { xml.cdata!("BRL") }
        end
      end
    end

    def operation_and_amount_for(habitation)
      types = @integration.allowed_business_types
      sale = types.include?("venda") ? cents_to_units(habitation.valor_venda_cents) : 0
      rent = types.include?("aluguel") ? cents_to_units(habitation.valor_locacao_cents) : 0
      rental_status = normalized_feature(habitation.status).include?("aluguel") || normalized_feature(habitation.status).include?("locacao")

      return ["ALQUILER", rent] if rent.positive? && (rental_status || !sale.positive?)

      ["VENTA", sale]
    end

    def add_publication!(xml, habitation)
      xml.publicacao do
        xml.tipoPublicacao publication_type_for(habitation)
      end
    end

    def publication_type_for(habitation)
      raw = habitation.respond_to?(:tipo_publicacao_imovelweb) ? habitation.tipo_publicacao_imovelweb : nil
      case normalized_feature(raw)
      when "destaque"
        "DESTACADO"
      when "super-destaque", "superdestaque"
        "SUPERDESTACADO"
      else
        DEFAULT_PUBLICATION_TYPE
      end
    end

    def map_visibility_for(habitation)
      raw = habitation.respond_to?(:mostrar_mapa_imovelweb) ? habitation.mostrar_mapa_imovelweb : nil
      case normalized_feature(raw)
      when "nao-mostrar", "no"
        "NO"
      when "exato", "exacto"
        "EXACTO"
      else
        DEFAULT_MAP_VISIBILITY
      end
    end

    def add_tours!(xml, habitation)
      xml.tours360 do
        xml.tour360 do
          xml.codigoTour360 { xml.cdata!(habitation.tour_virtual.to_s) }
        end
      end
    end

    def add_media!(xml, habitation)
      xml.multimidia do
        xml.imagens do
          image_urls_for(habitation).each do |url|
            xml.imagem do
              xml.titulo { xml.cdata!("") }
              xml.urlImagem { xml.cdata!(url) }
            end
          end
        end
      end
    end

    def image_urls_for(habitation)
      habitation.image_urls.filter_map { |url| absolute_url(url) }
    end

    def absolute_url(url)
      value = url.to_s.strip
      return nil if value.blank?
      return value if value.match?(%r{\Ahttps?://}i)

      host = @integration.tenant.public_base_url.to_s.sub(%r{/*\z}, "")
      return nil if host.blank?

      path = value.start_with?("/") ? value : "/#{value}"
      "#{host}#{path}"
    end

    def description_for(habitation)
      habitation.descricao_web.to_plain_text.presence ||
        habitation.meta_description.to_plain_text.presence ||
        "Sem descrição"
    rescue StandardError
      "Sem descrição"
    end

    def integer_or_zero(value)
      value.to_f.to_i
    end

    def cents_to_units(cents)
      cents.to_i / 100
    end

    def sanitize_cep(cep)
      cep.to_s.gsub(/\D/, "")
    end

    def coordinate(habitation, kind)
      source = habitation.address || habitation
      value = source.respond_to?(kind) ? source.public_send(kind) : nil
      return nil if value.blank?

      number = value.to_f
      return nil if number.zero?

      number
    end

    def normalized_category(value)
      normalized_feature(value)
    end

    def normalized_feature(value)
      I18n.transliterate(value.to_s.downcase)
        .strip
        .gsub(/[^a-z0-9]+/, "-")
        .gsub(/\A-+|-+\z/, "")
    end

    def state_name_for(uf)
      {
        "SC" => "Santa Catarina",
        "PR" => "Paraná",
        "SP" => "São Paulo",
        "RS" => "Rio Grande do Sul",
        "RJ" => "Rio de Janeiro",
        "MG" => "Minas Gerais",
        "ES" => "Espírito Santo",
        "DF" => "Distrito Federal",
        "GO" => "Goiás",
        "MS" => "Mato Grosso do Sul",
        "MT" => "Mato Grosso",
        "BA" => "Bahia"
      }[uf.to_s.upcase] || uf.to_s
    end
  end
end
