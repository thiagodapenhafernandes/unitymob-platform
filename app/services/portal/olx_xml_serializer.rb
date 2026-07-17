require "builder"

module Portal
  # OLX XML — Imovelweb / Wimoveis / OLX Brasil
  # Spec: https://developers.olx.com.br/anuncio/xml/real_estate/home.html
  # Tags em PT-BR: CodigoImovel, SubTipoImovel, TituloAnuncio, PrecoVenda, etc.
  class OlxXmlSerializer
    def initialize(habitations:, integration:)
      @habitations = habitations
      @integration = integration
      @identity = Tenants::PublicIdentity.new(integration.tenant)
    end

    def to_xml(target: nil)
      xml = Builder::XmlMarkup.new(**{ indent: 2 }.merge(target ? { target: target } : {}))
      xml.instruct!

      xml.Carga do
        xml.Imoveis do
          @habitations.each do |habitation|
            xml.Imovel do
              # Identificação
              xml.CodigoImovel habitation.codigo.to_s.first(20)
              xml.TituloAnuncio { xml.cdata!(title_for(habitation).first(90)) }
              xml.Observacao   { xml.cdata!(description_for(habitation).first(6000)) }

              # Categorização
              xml.TipoImovel    modalidade_for(habitation)
              xml.SubTipoImovel sub_tipo_for(habitation)

              # Endereço
              xml.UF    habitation.uf.to_s.upcase
              xml.Cidade   { xml.cdata!(habitation.cidade.to_s) }
              xml.Bairro   { xml.cdata!(habitation.bairro.to_s) }
              xml.Endereco { xml.cdata!(habitation.endereco.to_s) }
              xml.Numero  habitation.numero.to_s
              xml.Complemento habitation.complemento.to_s if habitation.complemento.to_s.strip.present?
              xml.CEP     sanitize_cep(habitation.cep)
              if (lat = coordinate(habitation, :latitude))
                xml.Latitude lat
              end
              if (lng = coordinate(habitation, :longitude))
                xml.Longitude lng
              end

              # Preços (PrecoVenda tem precedência sobre PrecoLocacao na OLX)
              xml.PrecoVenda    cents_to_units(habitation.valor_venda_cents)    if habitation.valor_venda_cents.to_i.positive?
              xml.PrecoLocacao  cents_to_units(habitation.valor_locacao_cents)  if habitation.valor_locacao_cents.to_i.positive?
              add_condominium_fee!(xml, habitation)
              xml.ValorIPTU     cents_to_units(habitation.valor_iptu_cents)    if habitation.valor_iptu_cents.to_i.positive?

              # Áreas
              xml.AreaUtil  integer_or_zero(habitation.area_privativa_m2)
              xml.AreaTotal integer_or_zero(habitation.area_total_m2)

              # Cômodos
              xml.QtdDormitorios habitation.dormitorios_qtd.to_i
              xml.QtdSuites      habitation.suites_qtd.to_i
              xml.QtdBanheiros   habitation.banheiros_qtd.to_i
              xml.QtdVagas       habitation.vagas_qtd.to_i

              # Características
              features = features_for(habitation)
              if features.any?
                xml.Caracteristicas do
                  features.each { |f| xml.Caracteristica { xml.cdata!(f) } }
                end
              end

              # Opções específicas do portal
              add_publication_options!(xml, habitation)

              # Fotos
              xml.Fotos do
                habitation.image_urls.first(20).each_with_index do |url, idx|
                  xml.Foto do
                    xml.URLArquivo url.to_s
                    xml.NomeArquivo File.basename(URI.parse(url.to_s).path.presence || "foto-#{idx + 1}.jpg") rescue "foto-#{idx + 1}.jpg"
                    xml.Principal idx.zero? ? "1" : "0"
                  end
                end
              end

              # Contato
              xml.Contato do
                xml.Nome     @identity.name
                xml.Email    @identity.email
                xml.Telefone @identity.phone
              end
            end
          end
        end
      end

      target ? nil : xml.target!
    end

    private

    def title_for(habitation)
      habitation.titulo_anuncio.presence || "Imóvel #{habitation.codigo}"
    end

    def description_for(habitation)
      habitation.descricao_web.to_plain_text.presence ||
        habitation.meta_description.to_plain_text.presence ||
        "Sem descrição"
    rescue
      "Sem descrição"
    end

    def modalidade_for(habitation)
      category = habitation.categoria.to_s.downcase
      case category
      when /comercial|sala|conjunto|loja|ponto|prédio|predio|galpão|galpao|industrial|escritório|escritorio/
        "Comercial"
      else
        "Residencial"
      end
    end

    def sub_tipo_for(habitation)
      category = habitation.categoria.to_s.downcase
      case category
      when /apartamento/                                 then "Apartamento"
      when /cobertura/                                   then "Cobertura"
      when /casa em condom/                              then "Casa em Condomínio"
      when /casa comercial/                              then "Casa Comercial"
      when /sobrado/                                     then "Sobrado"
      when /casa/                                        then "Casa"
      when /flat/                                        then "Flat"
      when /loft/                                        then "Loft"
      when /kitnet|studio/                               then "Kitnet"
      when /condomínio industrial|condominio industrial/ then "Galpão Industrial"
      when /condomínio|condominio/                       then "Condomínio"
      when /chácara|chacara/                             then "Chácara"
      when /sítio|sitio/                                 then "Sítio"
      when /terreno industrial|terreno comercial/        then "Terreno Comercial"
      when /terreno/                                     then "Terreno"
      when /galpão|galpao/                               then "Galpão"
      when /sala|conjunto/                               then "Sala/Conjunto"
      when /loja/                                        then "Loja"
      when /ponto comercial/                             then "Ponto Comercial"
      when /prédio comercial|predio comercial/           then "Prédio Comercial"
      when /área|area/                                   then "Área"
      when /empreendimento/                              then "Empreendimento"
      else                                                    "Outros"
      end
    end

    def features_for(habitation)
      values = []
      values.concat(Array(habitation.infra_estrutura))
      values.concat(Array(habitation.caracteristicas&.values)) if habitation.caracteristicas.respond_to?(:values)
      values.concat(Array(habitation.unique_features)) if habitation.respond_to?(:unique_features)
      values.map { |v| v.to_s.strip }.reject(&:blank?).uniq.first(40)
    end

    def add_publication_options!(xml, habitation)
      portal = @integration.portal
      if portal == "imovelweb" && habitation.respond_to?(:tipo_publicacao_imovelweb)
        xml.TipoPublicacao habitation.tipo_publicacao_imovelweb if habitation.tipo_publicacao_imovelweb.present?
        xml.MostrarMapa    habitation.mostrar_mapa_imovelweb    if habitation.mostrar_mapa_imovelweb.present?
      elsif portal == "imovelweb_2" && habitation.respond_to?(:tipo_publicacao_imovelweb_2)
        xml.TipoPublicacao habitation.tipo_publicacao_imovelweb_2 if habitation.tipo_publicacao_imovelweb_2.present?
        xml.MostrarMapa    habitation.mostrar_mapa_imovelweb_2    if habitation.mostrar_mapa_imovelweb_2.present?
      end
    end

    def add_condominium_fee!(xml, habitation)
      return unless habitation.valor_condominio_cents.to_i.positive?

      fee = cents_to_units(habitation.valor_condominio_cents)
      xml.PrecoCondominio fee
      xml.ValorCondominio fee if imovelweb_portal?
    end

    def imovelweb_portal?
      @integration.portal.to_s.in?(%w[imovelweb imovelweb_2])
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
      value = source.respond_to?(kind) ? source.send(kind) : nil
      return nil if value.blank?
      number = value.to_f
      return nil if number.zero?
      number
    end
  end
end
