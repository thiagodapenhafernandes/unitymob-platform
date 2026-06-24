require "json"

module InterestIntelligence
  class AiSummary
    def self.call(lead, profile: nil, matches: nil)
      new(lead, profile: profile, matches: matches).call
    end

    def initialize(lead, profile:, matches:)
      @lead = lead
      @profile = (profile || InterestIntelligence::ProfileBuilder.call(lead)).with_indifferent_access
      @matches = matches || InterestIntelligence::Matcher.call(lead)
      @settings = InterestIntelligence::Settings.current
    end

    def call
      return fallback_summary.merge("source" => "deterministic") unless Ai::PropertyContentService.connected?

      parsed = request_summary
      fallback_summary.merge(parsed).merge("source" => "openai")
    rescue => e
      Rails.logger.warn("[interest intelligence ai] #{e.class}: #{e.message}")
      fallback_summary.merge("source" => "deterministic", "error" => e.message)
    end

    private

    def request_summary
      response = OpenAi::Client.new(api_key: Ai::PropertyContentService.api_key).create_response(openai_payload)
      JSON.parse(extract_text(response))
    end

    def openai_payload
      {
        model: Ai::PropertyContentService.model,
        instructions: system_instructions,
        input: user_payload,
        text: {
          format: {
            type: "json_schema",
            name: "interest_intelligence_summary",
            strict: true,
            schema: {
              type: "object",
              additionalProperties: false,
              required: %w[classification summary broker_message lead_message rationale],
              properties: {
                classification: { type: "string", enum: %w[frio morno quente] },
                summary: { type: "string" },
                broker_message: { type: "string" },
                lead_message: { type: "string" },
                rationale: { type: "array", items: { type: "string" } }
              }
            }
          }
        }
      }
    end

    def system_instructions
      <<~TEXT
        Você é uma camada de apoio operacional para uma plataforma imobiliária.
        Classifique o interesse do lead e gere mensagens úteis para o corretor.
        Não assuma que uma recomendação pode ser enviada diretamente ao cliente quando a revisão humana estiver habilitada.
        Não invente dados de imóveis, preços, bairros ou preferências ausentes.
        Use português do Brasil, tom objetivo e operacional.

        DIRETRIZES DA CONTA:
        #{@settings.instructions}
      TEXT
    end

    def user_payload
      {
        lead: {
          id: @lead.id,
          nome: @lead.display_name,
          origem: @lead.origin,
          etapa: @lead.status
        },
        perfil: @profile,
        imoveis_compativeis: @matches.first(@settings["max_suggestions"].to_i).map do |result|
          habitation = result.habitation
          {
            id: habitation.id,
            codigo: habitation.codigo,
            titulo: habitation.display_title,
            score: result.score,
            motivos: result.reasons
          }
        end,
        revisao_humana_obrigatoria: @settings.enabled_value?("broker_review_required")
      }.to_json
    end

    def fallback_summary
      confidence = @profile[:confidence].to_i
      classification = if confidence >= 75 && @matches.any?
                         "quente"
                       elsif confidence >= 45
                         "morno"
                       else
                         "frio"
                       end

      {
        "classification" => classification,
        "summary" => "#{@lead.display_name}: perfil com #{confidence}% de confiança e #{@matches.size} imóvel(is) compatível(is).",
        "broker_message" => "Revise os imóveis sugeridos e escolha o melhor próximo contato para o lead.",
        "lead_message" => suggested_lead_message,
        "rationale" => fallback_rationale
      }
    end

    def suggested_lead_message
      return "Ainda estou analisando opções aderentes ao seu perfil." if @matches.blank?

      codes = @matches.first(3).map { |result| "##{result.habitation.codigo}" }.join(", ")
      "Separei algumas opções que parecem aderentes ao que você buscou: #{codes}. Posso te enviar os detalhes?"
    end

    def fallback_rationale
      criteria = @profile[:criteria].to_h.with_indifferent_access
      [
        ("Cidade: #{Array(criteria[:cities]).first(2).join(', ')}" if criteria[:cities].present?),
        ("Bairro: #{Array(criteria[:neighborhoods]).first(2).join(', ')}" if criteria[:neighborhoods].present?),
        ("Tipo: #{Array(criteria[:categories]).first(2).join(', ')}" if criteria[:categories].present?),
        ("Imóveis compatíveis: #{@matches.size}" if @matches.any?)
      ].compact
    end

    def extract_text(response)
      return response["output_text"] if response["output_text"].present?

      Array(response["output"]).flat_map { |item| Array(item["content"]) }.map { |content| content["text"] }.compact.join("\n")
    end
  end
end
