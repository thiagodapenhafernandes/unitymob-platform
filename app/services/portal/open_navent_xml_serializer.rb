require "builder"

module Portal
  class OpenNaventXmlSerializer
    def initialize(habitations:, integration:)
      @habitations = habitations
      @integration = integration
      @identity = Tenants::PublicIdentity.new(integration.tenant)
    end

    def to_xml(target: nil)
      xml = Builder::XmlMarkup.new(**{ indent: 2 }.merge(target ? { target: target } : {}))
      xml.instruct!

      xml.OpenNavent do
        xml.dataModificacao((Time.current.to_f * 1000).to_i.to_s)
        xml.Imoveis do
          @habitations.each do |habitation|
            xml.Imovel do
              xml.codigoAnuncio { xml.cdata!(habitation.codigo.to_s.first(100)) }
              xml.codigoReferencia { xml.cdata!(habitation.codigo.to_s.first(100)) }

              xml.tipoPropriedade do
                xml.tipo { xml.cdata!(property_type_for(habitation)) }
                xml.subTipo { xml.cdata!(property_subtype_for(habitation)) }
              end

              xml.operacao operation_for(habitation)
              add_price!(xml, habitation)
              xml.moeda "BRL"
              xml.titulo { xml.cdata!(title_for(habitation).first(120)) }
              xml.descricao { xml.cdata!(description_for(habitation).first(6000)) }

              add_location!(xml, habitation)
              add_details!(xml, habitation)
              add_features!(xml, habitation)
              add_images!(xml, habitation)
              add_contact!(xml)
            end
          end
        end
      end

      target ? nil : xml.target!
    end

    private

    def add_price!(xml, habitation)
      if habitation.valor_venda_cents.to_i.positive?
        xml.preco cents_to_units(habitation.valor_venda_cents)
      elsif habitation.valor_locacao_cents.to_i.positive?
        xml.preco cents_to_units(habitation.valor_locacao_cents)
      else
        xml.preco 0
      end
    end

    def add_location!(xml, habitation)
      xml.endereco do
        xml.pais "Brasil"
        xml.estado { xml.cdata!(attribute_for(habitation, :uf).to_s.upcase) }
        xml.cidade { xml.cdata!(attribute_for(habitation, :cidade)) }
        xml.bairro { xml.cdata!(attribute_for(habitation, :bairro)) }
        xml.logradouro { xml.cdata!(attribute_for(habitation, :endereco, :logradouro)) }
        xml.numero attribute_for(habitation, :numero)
        xml.complemento { xml.cdata!(attribute_for(habitation, :complemento)) } if attribute_for(habitation, :complemento).present?
        xml.cep sanitize_cep(attribute_for(habitation, :cep))
        if (lat = coordinate(habitation, :latitude))
          xml.latitude lat
        end
        if (lng = coordinate(habitation, :longitude))
          xml.longitude lng
        end
      end
    end

    def add_details!(xml, habitation)
      xml.quartos habitation.dormitorios_qtd.to_i
      xml.banheiros habitation.banheiros_qtd.to_i
      xml.vagas habitation.vagas_qtd.to_i
      xml.suites habitation.suites_qtd.to_i
      xml.areaUtil integer_or_zero(habitation.area_privativa_m2)
      xml.areaTotal integer_or_zero(habitation.area_total_m2)
      if habitation.valor_condominio_cents.to_i.positive?
        xml.valorCondominio cents_to_units(habitation.valor_condominio_cents)
      else
        xml.valorCondominio { xml.cdata!("Sem Condominio") }
      end
      xml.valorIptu cents_to_units(habitation.valor_iptu_cents) if habitation.valor_iptu_cents.to_i.positive?
    end

    def add_features!(xml, habitation)
      features = features_for(habitation)
      return if features.empty?

      xml.caracteristicas do
        features.each { |feature| xml.caracteristica { xml.cdata!(feature) } }
      end
    end

    def add_images!(xml, habitation)
      xml.imagens do
        habitation.image_urls.first(30).each_with_index do |url, index|
          xml.imagem do
            xml.url url.to_s
            xml.principal(index.zero? ? "1" : "0")
          end
        end
      end
    end

    def add_contact!(xml)
      xml.publicador do
        xml.nome { xml.cdata!(@identity.name.to_s) }
        xml.email @identity.email.to_s
        xml.telefone @identity.phone.to_s
      end
    end

    def title_for(habitation)
      habitation.titulo_anuncio.presence || "Imovel #{habitation.codigo}"
    end

    def description_for(habitation)
      plain_text_for(habitation.descricao_web).presence ||
        plain_text_for(habitation.meta_description).presence ||
        "Sem descricao"
    end

    def plain_text_for(value)
      value.respond_to?(:to_plain_text) ? value.to_plain_text : value.to_s
    rescue
      ""
    end

    def property_type_for(habitation)
      commercial?(habitation) ? "Comercial" : "Residencial"
    end

    def property_subtype_for(habitation)
      category = habitation.categoria.to_s.downcase
      case category
      when /apartamento/                                 then "Apartamento"
      when /cobertura/                                   then "Cobertura"
      when /casa em condom/                              then "Casa em Condominio"
      when /casa comercial/                              then "Casa Comercial"
      when /sobrado/                                     then "Sobrado"
      when /casa/                                        then "Casa"
      when /flat/                                        then "Flat"
      when /loft/                                        then "Loft"
      when /kitnet|studio/                               then "Kitnet"
      when /condomínio industrial|condominio industrial/ then "Galpao Industrial"
      when /condomínio|condominio/                       then "Condominio"
      when /chácara|chacara/                             then "Chacara"
      when /sítio|sitio/                                 then "Sitio"
      when /terreno industrial|terreno comercial/        then "Terreno Comercial"
      when /terreno/                                     then "Terreno"
      when /galpão|galpao/                               then "Galpao"
      when /sala|conjunto/                               then "Sala/Conjunto"
      when /loja/                                        then "Loja"
      when /ponto comercial/                             then "Ponto Comercial"
      when /prédio comercial|predio comercial/           then "Predio Comercial"
      when /área|area/                                   then "Area"
      when /empreendimento/                              then "Empreendimento"
      else                                                    "Outros"
      end
    end

    def commercial?(habitation)
      habitation.categoria.to_s.match?(/comercial|sala|conjunto|loja|ponto|prédio|predio|galpão|galpao|industrial|escritório|escritorio/)
    end

    def operation_for(habitation)
      return "Venda" if habitation.valor_venda_cents.to_i.positive?
      return "Aluguel" if habitation.valor_locacao_cents.to_i.positive?

      "Venda"
    end

    def features_for(habitation)
      values = []
      values.concat(Array(habitation.infra_estrutura))
      values.concat(Array(habitation.caracteristicas&.values)) if habitation.caracteristicas.respond_to?(:values)
      values.concat(Array(habitation.caracteristicas)) if habitation.caracteristicas.is_a?(Array)
      values.concat(Array(habitation.unique_features)) if habitation.respond_to?(:unique_features)
      values.map { |value| value.to_s.strip }.reject(&:blank?).uniq.first(40)
    end

    def attribute_for(habitation, method_name, address_method = method_name)
      address = habitation.address
      value = address.public_send(address_method) if address&.respond_to?(address_method)
      value.presence || (habitation.public_send(method_name) if habitation.respond_to?(method_name)).to_s
    end

    def coordinate(habitation, kind)
      source = habitation.address || habitation
      value = source.respond_to?(kind) ? source.public_send(kind) : nil
      return nil if value.blank?

      number = value.to_f
      return nil if number.zero?

      number
    end

    def sanitize_cep(cep)
      cep.to_s.gsub(/\D/, "")
    end

    def integer_or_zero(value)
      value.to_f.to_i
    end

    def cents_to_units(cents)
      cents.to_i / 100
    end
  end
end
