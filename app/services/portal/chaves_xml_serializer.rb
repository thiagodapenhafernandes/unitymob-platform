require "builder"

module Portal
  # Chaves na Mão XML - formato proprietário
  # Spec: https://tecnologiacnm.github.io/cnm-xml-documentation/arquivo/especificacoes/especificacoes-tags.html
  # Tags em PT-BR (referencia, transacao, finalidade, tipo, valor, etc.)
  # Lido 1x por dia pelo portal.
  class ChavesXmlSerializer
    RESIDENTIAL_TYPES = {
      /apartamento/i => "Apartamento",
      /casa.*condom[ií]nio|condom[ií]nio.*casa/i => "Casa / Sobrado em Condomínio",
      /cobertura/i => "Cobertura",
      /flat/i => "Flat",
      /kitnet|studio|st[uú]dio/i => "Kitnet / Stúdio",
      /loft/i => "Loft",
      /s[ií]tio|sitio|ch[aá]cara|chacara/i => "Sítio / Chácara",
      /terreno.*condom[ií]nio|condom[ií]nio.*terreno/i => "Terreno em Condomínio",
      /terreno|lote/i => "Terreno / Lote",
      /casa|sobrado/i => "Casa / Sobrado"
    }.freeze

    COMMERCIAL_TYPES = {
      /casa.*comercial|sobrado.*comercial/i => "Casa / Sobrado Comercial",
      /sala|conjunto|escrit[oó]rio/i => "Conj. Comercial / Sala",
      /fazenda/i => "Fazenda",
      /galp[aã]o|dep[oó]sito/i => "Galpão / Depósito",
      /garagem/i => "Garagem",
      /ponto|loja/i => "Ponto Comercial",
      /pr[eé]dio/i => "Prédio",
      /terreno/i => "Terreno comercial"
    }.freeze

    RENTAL_PERIODS = {
      "por_mes" => "1",
      "por_dia" => "2",
      "por_ano" => "3",
      "por_semana" => "4"
    }.freeze

    def initialize(habitations:, integration:)
      @habitations = habitations
      @integration = integration
      @tenant = integration.tenant
    end

    def to_xml(target: nil)
      xml = Builder::XmlMarkup.new(**{ indent: 2 }.merge(target ? { target: target } : {}))
      xml.instruct!

      xml.Document do
        xml.imoveis do
          @habitations.each do |habitation|
            xml.imovel do
              xml.referencia text_value(habitation.codigo)
              xml.codigo_cliente text_value(habitation.codigo)
              xml.link_cliente property_url_for(habitation)
              xml.titulo { xml.cdata!(title_for(habitation).first(120)) }
              xml.transacao transacao_for(habitation)
              xml.transacao2 secondary_transaction_for(habitation)
              xml.finalidade finalidade_for(habitation)
              xml.finalidade2 ""
              xml.destaque destaque_for(habitation)
              xml.tipo tipo_for(habitation)
              xml.tipo2 ""
              xml.valor valor_for(habitation)
              xml.valor_locacao rental_value_for(habitation)
              xml.valor_iptu money_value(habitation.valor_iptu_cents)
              xml.valor_condominio money_value(habitation.valor_condominio_cents)
              xml.area_total decimal_value(habitation.area_total_m2)
              xml.area_util decimal_value(habitation.area_privativa_m2)
              xml.quartos integer_value(habitation.dormitorios_qtd)
              xml.suites integer_value(habitation.suites_qtd)
              xml.garagem integer_value(habitation.vagas_qtd)
              xml.banheiro integer_value(habitation.banheiros_qtd)
              xml.closet ""
              xml.salas ""
              xml.despensa ""
              xml.bar ""
              xml.cozinha ""
              xml.quarto_empregada ""
              xml.escritorio ""
              xml.area_servico ""
              xml.lareira ""
              xml.varanda ""
              xml.lavanderia ""
              xml.estado habitation.uf.to_s.upcase.first(2)
              xml.cidade { xml.cdata!(text_value(habitation.cidade)) }
              xml.bairro { xml.cdata!(text_value(habitation.bairro)) }
              xml.cep sanitize_cep(habitation.cep).first(9)
              xml.endereco { xml.cdata!(text_value(habitation.endereco).first(200)) }
              xml.numero text_value(habitation.numero).first(10)
              xml.complemento text_value(habitation.complemento).first(20)
              xml.descritivo { xml.cdata!(description_for(habitation).first(3000)) }
              xml.fotos_imovel do
                habitation.image_urls.first(30).each do |url|
                  xml.foto do
                    xml.url url.to_s
                    xml.data_atualizacao timestamp_for(habitation)
                  end
                end
              end
              xml.data_atualizacao timestamp_for(habitation)
              xml.latitude coordinate(habitation, :latitude).to_s
              xml.longitude coordinate(habitation, :longitude).to_s
              xml.video ""
              xml.area_comum
              xml.area_privativa
              xml.aceita_troca "0"
              xml.periodo_locacao rental_period_for(habitation)
              xml.esconder_endereco_imovel "0"
              xml.tour_360 ""
              xml.aceita_pet ""
            end
          end
        end
      end

      target ? nil : xml.target!
    end

    private

    def transacao_for(habitation)
      # V = Venda, L = Locação. Venda tem precedência se ambos.
      habitation.valor_venda_cents.to_i.positive? ? "V" : "L"
    end

    def finalidade_for(habitation)
      # RE = residencial, CO = comercial, RU = rural
      category = habitation.categoria.to_s.downcase
      case category
      when /chácara|chacara|sítio|sitio|fazenda|rural/ then "RU"
      when /comercial|sala|conjunto|loja|ponto|prédio comercial|predio comercial|galpão|galpao|industrial|escritório|escritorio/
        "CO"
      else
        "RE"
      end
    end

    def tipo_for(habitation)
      category = habitation.categoria.to_s
      mapping = finalidade_for(habitation) == "CO" ? COMMERCIAL_TYPES : RESIDENTIAL_TYPES
      mapping.each do |pattern, value|
        return value if category.match?(pattern)
      end

      finalidade_for(habitation) == "CO" ? "Conj. Comercial / Sala" : "Apartamento"
    end

    def valor_for(habitation)
      # Valor principal (venda se houver, senão locação)
      cents = habitation.valor_venda_cents.to_i.positive? ? habitation.valor_venda_cents : habitation.valor_locacao_cents
      format_money(cents)
    end

    def destaque_for(habitation)
      explicit = habitation.respond_to?(:destaque_chaves_na_mao) ? habitation.destaque_chaves_na_mao : nil
      return "1" if explicit.to_s.casecmp("sim").zero?
      return "0" if explicit.to_s.casecmp("nao").zero? || explicit.to_s.casecmp("não").zero?
      habitation.destaque_web_flag ? "1" : "0"
    end

    def title_for(habitation)
      habitation.titulo_anuncio.presence ||
        [tipo_for(habitation), habitation.bairro, habitation.cidade].compact_blank.join(" - ").presence ||
        "Imóvel #{habitation.codigo}"
    end

    def description_for(habitation)
      habitation.descricao_web.to_plain_text.presence ||
        habitation.meta_description.to_plain_text.presence ||
        "Sem descrição"
    rescue
      "Sem descrição"
    end

    def secondary_transaction_for(habitation)
      return "L" if habitation.valor_venda_cents.to_i.positive? && habitation.valor_locacao_cents.to_i.positive?

      ""
    end

    def rental_value_for(habitation)
      return "" unless habitation.valor_venda_cents.to_i.positive? && habitation.valor_locacao_cents.to_i.positive?

      format_money(habitation.valor_locacao_cents)
    end

    def rental_period_for(habitation)
      return "" unless locacao_available?(habitation)

      RENTAL_PERIODS[habitation.periodo_locacao_chaves_na_mao.to_s] || ""
    end

    def locacao_available?(habitation)
      habitation.valor_locacao_cents.to_i.positive?
    end

    def property_url_for(habitation)
      slug = habitation.slug.presence || habitation.codigo
      return "" if slug.blank?

      "#{public_base_url}/imovel/#{slug}"
    end

    def public_base_url
      @public_base_url ||= begin
        host = @tenant&.tenant_domains&.active&.primary_first&.first&.hostname
        if host.present?
          "https://#{host}"
        else
          ENV.fetch("APP_HOST", "https://example.com").to_s.delete_suffix("/")
        end
      end
    end

    def format_money(cents)
      format("%.2f", cents.to_i / 100.0)
    end

    def format_decimal(value)
      format("%.2f", value.to_f)
    end

    def money_value(cents)
      return "" unless cents.to_i.positive?

      format_money(cents)
    end

    def decimal_value(value)
      return "" unless value.to_f.positive?

      format_decimal(value)
    end

    def integer_value(value)
      integer = value.to_i
      return "" unless integer.positive?

      integer.to_s
    end

    def text_value(value)
      value.to_s.strip
    end

    def timestamp_for(habitation)
      time = habitation.updated_at || habitation.created_at || Time.current
      time.strftime("%Y-%m-%d %H:%M:%S")
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
