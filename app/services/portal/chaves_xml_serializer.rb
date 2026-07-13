require "builder"

module Portal
  # Chaves na Mão XML — formato proprietário
  # Spec: https://tecnologiacnm.github.io/cnm-xml-documentation/arquivo/especificacoes/especificacoes-tags.html
  # Tags em PT-BR (referencia, transacao, finalidade, tipo, valor, etc.)
  # Lido 1x por dia pelo portal.
  class ChavesXmlSerializer
    CONTACT_NAME  = "SALUTE IMOVEIS"
    CONTACT_EMAIL = "contato@saluteimoveis.com.br"
    CONTACT_PHONE = "(47) 3311-1067"

    def initialize(habitations:, integration:)
      @habitations = habitations
      @integration = integration
    end

    def to_xml(target: nil)
      xml = Builder::XmlMarkup.new(**{ indent: 2 }.merge(target ? { target: target } : {}))
      xml.instruct!

      xml.imoveis(gerado_em: Time.current.iso8601, total: @habitations.respond_to?(:size) ? @habitations.size : nil) do
        @habitations.each do |habitation|
          xml.imovel do
            # Identificação obrigatória
            xml.referencia habitation.codigo
            xml.transacao  transacao_for(habitation)
            xml.finalidade finalidade_for(habitation)
            xml.tipo       tipo_for(habitation)
            xml.valor      valor_for(habitation)

            # Localização obrigatória
            xml.estado habitation.uf.to_s.upcase
            xml.cidade { xml.cdata!(habitation.cidade.to_s) }
            xml.bairro { xml.cdata!(habitation.bairro.to_s) }

            # Endereço opcional
            xml.endereco { xml.cdata!(habitation.endereco.to_s) } if habitation.endereco.present?
            xml.numero    habitation.numero.to_s if habitation.numero.present?
            xml.complemento habitation.complemento.to_s if habitation.complemento.to_s.strip.present?
            xml.cep       sanitize_cep(habitation.cep) if habitation.cep.present?

            if (lat = coordinate(habitation, :latitude))
              xml.latitude lat
            end
            if (lng = coordinate(habitation, :longitude))
              xml.longitude lng
            end

            # Descrição obrigatória (max 3000 chars)
            xml.descritivo { xml.cdata!(description_for(habitation).first(3000)) }

            # Destaque (0 ou 1)
            xml.destaque destaque_for(habitation)

            # Transação secundária e valor de locação se aplicável
            if habitation.valor_venda_cents.to_i.positive? && habitation.valor_locacao_cents.to_i.positive?
              xml.transacao2     "L"
              xml.valor_locacao  format_money(habitation.valor_locacao_cents)
            end

            # Áreas
            xml.area_total format_decimal(habitation.area_total_m2) if habitation.area_total_m2.to_f.positive?
            xml.area_util  format_decimal(habitation.area_privativa_m2) if habitation.area_privativa_m2.to_f.positive?

            # Cômodos
            xml.quartos   habitation.dormitorios_qtd.to_i if habitation.dormitorios_qtd.to_i.positive?
            xml.suites    habitation.suites_qtd.to_i      if habitation.suites_qtd.to_i.positive?
            xml.banheiro  habitation.banheiros_qtd.to_i   if habitation.banheiros_qtd.to_i.positive?
            xml.garagem   habitation.vagas_qtd.to_i       if habitation.vagas_qtd.to_i.positive?

            # Valores adicionais
            xml.condominio format_money(habitation.valor_condominio_cents) if habitation.valor_condominio_cents.to_i.positive?
            xml.iptu       format_money(habitation.valor_iptu_cents)       if habitation.valor_iptu_cents.to_i.positive?

            # Opções específicas do portal
            if habitation.respond_to?(:periodo_locacao_chaves_na_mao) && habitation.periodo_locacao_chaves_na_mao.present?
              xml.periodo_locacao habitation.periodo_locacao_chaves_na_mao
            end

            # Características (lista plana)
            features = features_for(habitation)
            if features.any?
              xml.caracteristicas do
                features.each { |f| xml.caracteristica { xml.cdata!(f) } }
              end
            end

            # Fotos (nested)
            xml.fotos_imovel do
              habitation.image_urls.first(20).each_with_index do |url, idx|
                xml.foto do
                  xml.url url.to_s
                  xml.principal idx.zero? ? "1" : "0"
                  xml.ordem (idx + 1)
                end
              end
            end

            # Contato
            xml.contato do
              xml.nome     CONTACT_NAME
              xml.email    CONTACT_EMAIL
              xml.telefone CONTACT_PHONE
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
      # Tipo do imóvel — texto livre que faz sentido para o portal
      habitation.categoria.presence || "Imóvel"
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

    def description_for(habitation)
      habitation.descricao_web.to_plain_text.presence ||
        habitation.meta_description.to_plain_text.presence ||
        "Sem descrição"
    rescue
      "Sem descrição"
    end

    def features_for(habitation)
      values = []
      values.concat(Array(habitation.infra_estrutura))
      values.concat(Array(habitation.caracteristicas&.values)) if habitation.caracteristicas.respond_to?(:values)
      values.concat(Array(habitation.unique_features)) if habitation.respond_to?(:unique_features)
      values.map { |v| v.to_s.strip }.reject(&:blank?).uniq.first(40)
    end

    def format_money(cents)
      # Reais com 2 casas decimais e ponto como separador (spec: "valor com ponto (.) para casas decimais")
      format("%.2f", cents.to_i / 100.0)
    end

    def format_decimal(value)
      format("%.2f", value.to_f)
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
