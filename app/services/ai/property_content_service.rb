module Ai
  class PropertyContentService
    DEFAULT_MODEL = "gpt-4.1-mini".freeze
    API_KEY_SETTING = "openai_api_key".freeze
    MODEL_SETTING = "openai_model".freeze
    PROMPT_SETTING = "openai_property_enrichment_prompt".freeze
    TEMPERATURE_SETTING = "openai_property_enrichment_temperature".freeze
    TOP_P_SETTING = "openai_property_enrichment_top_p".freeze
    FREQUENCY_PENALTY_SETTING = "openai_property_enrichment_frequency_penalty".freeze
    PRESENCE_PENALTY_SETTING = "openai_property_enrichment_presence_penalty".freeze
    DEFAULT_TEMPERATURE = 0.2
    DEFAULT_TOP_P = 0.8
    DEFAULT_FREQUENCY_PENALTY = 0.5
    DEFAULT_PRESENCE_PENALTY = 0.2
    RESPONSE_PARAMETER_RANGES = {
      temperature: 0.0..2.0,
      top_p: 0.0..1.0,
      frequency_penalty: -2.0..2.0,
      presence_penalty: -2.0..2.0
    }.freeze
    RESPONSE_PARAMETER_DEFAULTS = {
      temperature: DEFAULT_TEMPERATURE,
      top_p: DEFAULT_TOP_P,
      frequency_penalty: DEFAULT_FREQUENCY_PENALTY,
      presence_penalty: DEFAULT_PRESENCE_PENALTY
    }.freeze
    RESPONSE_PARAMETER_SETTINGS = {
      temperature: TEMPERATURE_SETTING,
      top_p: TOP_P_SETTING,
      frequency_penalty: FREQUENCY_PENALTY_SETTING,
      presence_penalty: PRESENCE_PENALTY_SETTING
    }.freeze

    DEFAULT_PROMPT = <<~PROMPT.freeze
      Para Título:
      O título deve ser da seguinte forma:
      1- Tipo (Apartamento, Casa, Terreno, Sala Comercial, Duplex);
      2 - Colocar se é venda ou Aluguel;
      3 - Número de dormitórios, se tiver 3 dormitórios, 3 suítes, dar preferência ao nome suítes. se for do tipo 3 dormitórios 2 suítes, colocar 3 dormitórios;
      4 - Localização, bairro. (EX: Praia Brava, - Barra Sul,);
      Exemplo: Apartamento aluguel anual 3 dormitórios no Centro
      EX: Duplex aluguel anual 3 suítes, na Barra Sul;
      Regra para número de quartos: Se o número de suítes for igual ao de quartos no título usar “suítes” se o número de quartos for maior que o número de suítes usar “dormitórios”

      Para descrição:
      Crie uma descrição persuasiva e otimizada para SEO de um imóvel para um site imobiliário. A descrição deve atrair potenciais compradores que é um público AAA, ou locatários e destacar os principais diferenciais do imóvel, fazendo uso de palavras-chave relacionadas ao mercado imobiliário e ao imóvel. Evite palavras exageradas como incrível, maravilhoso, perfeito, sofisticado ou que deem características que não podemos garantir como estado de conservação etc. Estruture sua resposta sem tópicos, apenas texto corrido.

      Use na descrição coisas que ajudem a vender o imóvel como: Frente mar, quadra mar, mobiliado e decorado, lazer completo. Ordem de importância das características: Frente mar, quadra mar, mobiliado e decorado, churrasqueira à carvão, sacada com churrasqueira à carvão, vista para o mar. Isso deve ser analisado no cadastro de cada imóvel e usado de modo coerente.

      Regras:
      - Use números em numerais.
      - Não use o nome do empreendimento nem o endereço completo.
      - Use apenas a localização comercial/bairro, sem escrever a palavra "bairro" antes.
      - Distância da praia só deve ser mencionada se for menor que 500 metros.
      - Não seja muito extenso.
      - Divida em parágrafos nesta ordem: dados do apartamento, dados do empreendimento quando houver, dados da localização, CTA para mais informações ou visita, frases fixas finais.
      - Não coloque informações inventadas.
      - Use tom profissional, envolvente e amigável.

      Use sempre ao final as seguintes frases, sem alterar:
      Não perca a oportunidade de viver em um dos destinos mais desejados de Santa Catarina!
      A imobiliária está localizada na região de atuação informada pela conta.
      O seu DNA é o atendimento diferenciado para quem quer comprar ou vender um imóvel. Fale com a gente em um dos nossos canais de atendimento ou venha nos fazer uma visita.
      Os valores estão sujeitos a alteração sem aviso prévio.

      Para locação, quando as taxas estiverem inclusas ou não houver informação contrária, inclua também:
      O valor do aluguel já contempla todas as taxas, garantindo mais praticidade e comodidade para você. Sem surpresas no final do mês, apenas o valor anunciado!
    PROMPT

    def self.api_key(tenant: Current.tenant)
      Setting.tenant_get(API_KEY_SETTING, nil, tenant: tenant).to_s
    end

    def self.model(tenant: Current.tenant)
      Setting.tenant_get(MODEL_SETTING, DEFAULT_MODEL, tenant: tenant).to_s.presence || DEFAULT_MODEL
    end

    def self.resolved_model(tenant: Current.tenant)
      OpenAi::ModelCatalog.resolve_response_model(model(tenant: tenant))
    end

    def self.instructions(tenant: Current.tenant)
      fallback = default_prompt(tenant)
      Setting.tenant_get(PROMPT_SETTING, fallback, tenant: tenant).to_s.presence || fallback
    end

    def self.response_parameters(tenant: Current.tenant)
      RESPONSE_PARAMETER_SETTINGS.each_with_object({}) do |(key, setting_key), values|
        values[key] = normalize_response_parameter(
          key,
          Setting.tenant_get(setting_key, RESPONSE_PARAMETER_DEFAULTS.fetch(key), tenant: tenant)
        )
      end
    end

    def self.normalize_response_parameter(key, value)
      fallback = RESPONSE_PARAMETER_DEFAULTS.fetch(key)
      number = Float(value)
      range = RESPONSE_PARAMETER_RANGES.fetch(key)
      number = fallback unless number.finite? && number.between?(range.begin, range.end)
      number.round(2)
    rescue ArgumentError, TypeError
      fallback
    end

    def self.default_prompt(tenant)
      return DEFAULT_PROMPT if tenant.blank?

      identity = Tenants::PublicIdentity.new(tenant)
      city = identity.primary_city.presence || "sua região"
      DEFAULT_PROMPT
        .gsub("A imobiliária está localizada na região de atuação informada pela conta.", "A #{identity.name} atua em #{city} e região.")
        .gsub("Praia Brava", city)
        .gsub("Barra Sul", city)
    end

    def self.connected?(tenant: Current.tenant)
      api_key(tenant: tenant).present?
    end

    def initialize(habitation, admin_user: nil)
      @habitation = habitation
      @admin_user = admin_user
    end

    def generate_suggestion!
      parsed = request_generation
      suggestion = @habitation.ai_property_suggestions.create!(
        admin_user: @admin_user,
        status: "pending",
        generated_title: parsed.fetch("title").to_s.strip,
        generated_description: parsed.fetch("description").to_s.strip,
        generated_seo_keywords: Array(parsed["seo_keywords"]).join(", "),
        raw_response: parsed.to_json
      )

      suggestion
    rescue => e
      @habitation.ai_property_suggestions.create!(
        admin_user: @admin_user,
        status: "failed",
        error_message: e.message
      )
      raise
    end

    def apply!(suggestion)
      raise "Sugestão inválida para este imóvel." unless suggestion.habitation_id == @habitation.id
      raise "Sugestão sem título." if suggestion.generated_title.blank?
      raise "Sugestão sem descrição." if suggestion.generated_description.blank?

      html_description = description_html(suggestion.generated_description)
      plain_description = plain_text(suggestion.generated_description)

      @habitation.titulo_anuncio = suggestion.generated_title
      @habitation.descricao_web = html_description
      @habitation[:descricao_web] = html_description if @habitation.has_attribute?(:descricao_web)
      @habitation.meta_title = suggestion.generated_title if @habitation.respond_to?(:meta_title=)
      if @habitation.respond_to?(:meta_description=)
        @habitation.meta_description = plain_description
        @habitation[:meta_description] = plain_description if @habitation.has_attribute?(:meta_description)
      end
      @habitation.meta_keywords = suggestion.seo_keywords_list.join(", ") if suggestion.seo_keywords_list.any?
      @habitation.save!

      suggestion.update!(status: "applied", applied_at: Time.current)
      suggestion
    end

    private

    def request_generation
      response = OpenAi::Client.new(api_key: self.class.api_key(tenant: @habitation.tenant)).create_response(
        openai_payload,
        fallback_model: OpenAi::ModelCatalog.fallback_response_model(self.class.resolved_model(tenant: @habitation.tenant))
      )
      text = extract_text(response)
      parsed = JSON.parse(text)
      validate_response!(parsed)
      parsed
    end

    def openai_payload
      {
        model: self.class.resolved_model(tenant: @habitation.tenant),
        instructions: system_instructions,
        input: user_payload,
        **self.class.response_parameters(tenant: @habitation.tenant),
        text: {
          format: {
            type: "json_schema",
            name: "property_content_suggestion",
            strict: true,
            schema: {
              type: "object",
              additionalProperties: false,
              required: ["title", "description", "seo_keywords"],
              properties: {
                title: { type: "string" },
                description: { type: "string" },
                seo_keywords: {
                  type: "array",
                  items: { type: "string" }
                }
              }
            }
          }
        }
      }
    end

    def system_instructions
      <<~TEXT
        Você é um redator imobiliário da #{Tenants::PublicIdentity.new(@habitation.tenant).name}.
        Siga estritamente as instruções configuradas pelo administrador.
        Nunca invente informações ausentes no cadastro.
        Retorne apenas JSON no formato solicitado.

        INSTRUÇÕES DO ADMINISTRADOR:
        #{self.class.instructions(tenant: @habitation.tenant)}
      TEXT
    end

    def user_payload
      {
        tarefa: "Gerar sugestão de título, descrição e palavras-chave SEO para prévia. Não aplicar no imóvel.",
        imovel: property_payload
      }.to_json
    end

    def property_payload
      {
        id: @habitation.id,
        codigo: @habitation.codigo,
        categoria: @habitation.categoria,
        status: @habitation.status,
        situacao: @habitation.situacao,
        tipo: @habitation.tipo,
        nome_empreendimento: @habitation.nome_empreendimento,
        codigo_empreendimento: @habitation.codigo_empreendimento,
        unidade_numero: @habitation.unidade_numero,
        titulo_atual: @habitation.titulo_anuncio,
        descricao_atual: sanitized_text(@habitation.display_description),
        cidade: @habitation.cidade,
        bairro: @habitation.bairro,
        bairro_comercial: @habitation.address&.bairro_comercial,
        endereco: address_payload,
        empreendimento: development_payload,
        dormitorios: @habitation.dormitorios_qtd,
        suites: @habitation.suites_qtd,
        demi_suites: @habitation.demi_suites_qtd,
        banheiros: @habitation.banheiros_qtd,
        salas: @habitation.salas_qtd,
        varandas: @habitation.varandas_qtd,
        vagas: @habitation.vagas_qtd,
        tipo_vaga: @habitation.tipo_vaga,
        numero_box: @habitation.numero_box,
        andar: @habitation.andar,
        elevadores: @habitation.elevadores_qtd,
        area_privativa_m2: @habitation.area_privativa_m2,
        area_total_m2: @habitation.area_total_m2,
        area_terreno_m2: @habitation.area_terreno_m2,
        area_util_m2: @habitation.area_util_m2,
        dimensoes_terreno: @habitation.dimensoes_terreno,
        topografia: @habitation.topografia,
        valor_venda_cents: @habitation.valor_venda_cents,
        valor_locacao_cents: @habitation.valor_locacao_cents,
        valor_total_aluguel_cents: @habitation.valor_total_aluguel_cents,
        valor_condominio_cents: @habitation.valor_condominio_cents,
        valor_iptu_cents: @habitation.valor_iptu_cents,
        valor_por_m2_cents: @habitation.valor_por_m2_cents,
        valor_promocional_cents: @habitation.valor_promocional_cents,
        valor_venda_anterior_cents: @habitation.valor_venda_anterior_cents,
        valor_locacao_anterior_cents: @habitation.valor_locacao_anterior_cents,
        mobiliado: @habitation.mobiliado_flag,
        decorado: @habitation.decorado_flag,
        quadra_mar: @habitation.quadra_mar_flag,
        vista_frente_mar: @habitation.vista_frente_mar_flag,
        frente_mar_avenida_atlantica: @habitation.frente_mar_avenida_atlantica_flag,
        aceita_permuta: @habitation.aceita_permuta_flag,
        aceita_financiamento: @habitation.aceita_financiamento_flag,
        aceita_parcelamento: @habitation.aceita_parcelamento_flag,
        ocupacao: @habitation.ocupacao_status,
        estado_conservacao: @habitation.estado_conservacao,
        construtora: @habitation.constructor_name,
        tipo_fachada: @habitation.tipo_fachada,
        data_entrega: @habitation.data_entrega,
        ano_construcao: @habitation.ano_construcao,
        andares: @habitation.andares_qtd,
        aptos_por_andar: @habitation.aptos_andar,
        aptos_no_edificio: @habitation.aptos_edificio,
        distancia_praia_m: @habitation.distancia_praia.presence,
        face: @habitation.face,
        caracteristicas: @habitation.property_features_for_display,
        infraestrutura: @habitation.leisure_features_for_display,
        destaques: @habitation.unique_features,
        imediacoes: @habitation.address&.imediacoes,
        midia: media_payload,
        descricao_empreendimento: sanitized_text(@habitation.descricao_empreendimento)
      }
    end

    def development_payload
      development = @habitation.empreendimento
      return nil if development.blank?

      {
        codigo: development.codigo,
        nome: development.nome_empreendimento,
        titulo: development.titulo_anuncio,
        cidade: development.cidade,
        bairro: development.bairro,
        bairro_comercial: development.bairro_comercial,
        descricao: sanitized_text(development.display_description),
        infraestrutura: development.leisure_features_for_display,
        destaques: development.unique_features,
        construtora: development.constructor_name,
        tipo_fachada: development.tipo_fachada,
        data_entrega: development.data_entrega,
        ano_construcao: development.ano_construcao,
        andares: development.andares_qtd,
        aptos_por_andar: development.aptos_andar,
        aptos_no_edificio: development.aptos_edificio,
        elevadores: development.elevadores_qtd
      }.compact
    end

    def media_payload
      {
        possui_fotos: @habitation.has_any_photo?,
        classificacao_fotos: @habitation.foto_classificacao,
        usa_fotos_empreendimento: @habitation.use_development_photos?
      }
    end

    def sanitized_text(value)
      ActionController::Base.helpers.strip_tags(value.to_s).squish
    end

    def address_payload
      address = @habitation.address

      {
        tipo_endereco: address&.tipo_endereco.presence || @habitation.tipo_endereco,
        logradouro: address&.logradouro.presence || @habitation.logradouro,
        numero: address&.numero.presence || @habitation.numero,
        complemento: address&.complemento.presence || @habitation.complemento,
        bairro: address&.bairro.presence || @habitation.bairro,
        bairro_comercial: address&.bairro_comercial.presence || @habitation.bairro_comercial,
        cidade: address&.cidade.presence || @habitation.cidade,
        uf: address&.uf.presence || @habitation.uf,
        cep: address&.cep.presence || @habitation.cep,
        pais: address&.pais.presence || @habitation.pais,
        bloco: @habitation.bloco,
        lote: @habitation.lote,
        quadra: @habitation.quadra,
        latitude: address&.latitude.presence || @habitation.latitude,
        longitude: address&.longitude.presence || @habitation.longitude,
        imediacoes: address&.imediacoes,
        localizacao_publica: @habitation.public_map_display_mode,
        vista_da_rua: @habitation.public_street_view_mode
      }.compact
    end

    def extract_text(response)
      return response["output_text"] if response["output_text"].present?

      Array(response["output"]).flat_map { |item| Array(item["content"]) }.map { |content| content["text"] }.compact.join("\n")
    end

    def validate_response!(parsed)
      raise "Resposta da IA sem título." if parsed["title"].blank?
      raise "Resposta da IA sem descrição." if parsed["description"].blank?
      raise "Resposta da IA sem palavras-chave SEO." unless parsed["seo_keywords"].is_a?(Array)
    end

    def description_html(text)
      paragraphs = text.to_s
        .split(/\n{2,}/)
        .map { |paragraph| paragraph.gsub(/\n+/, " ").squish }
        .reject(&:blank?)

      return text.to_s if paragraphs.blank?

      paragraphs.map { |paragraph| "<p>#{ERB::Util.html_escape(paragraph)}</p>" }.join
    end

    def plain_text(text)
      ActionController::Base.helpers.strip_tags(description_html(text)).squish
    end
  end
end
