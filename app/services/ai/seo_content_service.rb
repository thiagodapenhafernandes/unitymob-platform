module Ai
  class SeoContentService
    DEFAULT_PROMPT = <<~PROMPT.freeze
      Você é um especialista sênior em SEO imobiliário para Balneário Camboriú, Praia Brava e região.
      O foco é dominar buscas relevantes, com conteúdo útil, não repetitivo, tecnicamente correto e pronto para os principais buscadores.

      Priorize:
      - páginas de listagem de imóveis por intenção de busca;
      - títulos únicos, naturais e com localização;
      - descrições com promessa clara, sem exageros e sem informações falsas;
      - evitar canibalização, duplicidade e páginas pobres;
      - sugerir noindex quando a página não tiver valor real de busca ou for paginação/filtro fraco;
      - respeitar boas práticas de Google e buscadores modernos.

      Gere sempre conteúdo em português do Brasil.
    PROMPT

    PROMPT_SETTING = "seo_ai_strategy_prompt".freeze

    def self.connected?
      Ai::PropertyContentService.connected?
    end

    def self.instructions(tenant: Current.tenant)
      fallback = default_prompt(tenant)
      Setting.get(PROMPT_SETTING, fallback, tenant: tenant).to_s.presence || fallback
    end

    def self.default_prompt(tenant)
      return DEFAULT_PROMPT if tenant.blank?

      identity = Tenants::PublicIdentity.new(tenant)
      city = identity.primary_city.presence || "a região de atuação da imobiliária"
      DEFAULT_PROMPT.gsub("Balneário Camboriú, Praia Brava e região", city)
    end

    def self.save_instructions!(value)
      Setting.set(PROMPT_SETTING, value.to_s, "Instruções estratégicas da IA para SEO")
    end

    def initialize(seo_setting)
      @seo_setting = seo_setting
    end

    def generate!
      @seo_setting.update!(ai_status: "generating", ai_error_message: nil)
      parsed = request_generation

      @seo_setting.update!(
        meta_title: parsed.fetch("meta_title").to_s.strip,
        meta_description: parsed.fetch("meta_description").to_s.strip,
        meta_keywords: Array(parsed["keywords"]).join(", "),
        intro_text: parsed["intro_text"].to_s.strip.presence,
        og_title: parsed["og_title"].to_s.presence || parsed.fetch("meta_title").to_s.strip,
        og_description: parsed["og_description"].to_s.presence || parsed.fetch("meta_description").to_s.strip,
        robots_index: parsed.key?("robots_index") ? parsed["robots_index"] : @seo_setting.robots_index,
        robots_follow: parsed.key?("robots_follow") ? parsed["robots_follow"] : @seo_setting.robots_follow,
        ai_insights: Array(parsed["insights"]).join("\n"),
        ai_status: "generated",
        ai_generated_at: Time.current,
        ai_error_message: nil
      )

      @seo_setting
    rescue => e
      @seo_setting.update!(ai_status: "failed", ai_error_message: e.message)
      raise
    end

    private

    def request_generation
      response = OpenAi::Client.new(api_key: Ai::PropertyContentService.api_key).create_response(openai_payload)
      parsed = JSON.parse(extract_text(response))
      validate!(parsed)
      parsed
    end

    def openai_payload
      {
        model: Ai::PropertyContentService.model,
        instructions: system_instructions,
        input: page_payload.to_json,
        text: {
          format: {
            type: "json_schema",
            name: "seo_page_suggestion",
            strict: true,
            schema: {
              type: "object",
              additionalProperties: false,
              required: ["meta_title", "meta_description", "keywords", "intro_text", "og_title", "og_description", "robots_index", "robots_follow", "insights"],
              properties: {
                meta_title: { type: "string" },
                meta_description: { type: "string" },
                keywords: { type: "array", items: { type: "string" } },
                intro_text: { type: "string" },
                og_title: { type: "string" },
                og_description: { type: "string" },
                robots_index: { type: "boolean" },
                robots_follow: { type: "boolean" },
                insights: { type: "array", items: { type: "string" } }
              }
            }
          }
        }
      }
    end

    def system_instructions
      <<~TEXT
        Você gera SEO técnico para páginas públicas de uma imobiliária.
        Respeite as instruções estratégicas abaixo e nunca invente ofertas, contagens ou informações ausentes.
        Quando a página for de listagem, gere intro_text com 150 a 250 palavras em 2 ou 3 parágrafos, útil para humanos,
        sem tópicos, explicando a intenção da página, para quem ela serve e como refinar a busca.
        Se a página não for uma listagem, retorne intro_text como string vazia.
        Retorne apenas JSON no schema solicitado.

        INSTRUÇÕES ESTRATÉGICAS:
        #{self.class.instructions(tenant: @seo_setting.tenant)}
      TEXT
    end

    def page_payload
      {
        tarefa: "Gerar SEO técnico e insights para a página pública.",
        pagina: {
          canonical_key: @seo_setting.canonical_key,
          page_name: @seo_setting.page_name,
          page_type: @seo_setting.page_type,
          canonical_path: @seo_setting.canonical_path,
          normalized_params: @seo_setting.normalized_params,
          current_meta_title: @seo_setting.meta_title,
          current_meta_description: @seo_setting.meta_description,
          current_keywords: @seo_setting.meta_keywords,
          current_intro_text: @seo_setting.intro_text,
          current_score: @seo_setting.seo_score,
          access_count: @seo_setting.access_count
        }
      }
    end

    def extract_text(response)
      return response["output_text"] if response["output_text"].present?

      Array(response["output"]).flat_map { |item| Array(item["content"]) }.map { |content| content["text"] }.compact.join("\n")
    end

    def validate!(parsed)
      raise "Resposta da IA sem meta title." if parsed["meta_title"].blank?
      raise "Resposta da IA sem meta description." if parsed["meta_description"].blank?
      raise "Resposta da IA sem keywords." unless parsed["keywords"].is_a?(Array)
      raise "Resposta da IA sem texto introdutório." unless parsed.key?("intro_text")
      raise "Resposta da IA sem insights." unless parsed["insights"].is_a?(Array)
    end
  end
end
