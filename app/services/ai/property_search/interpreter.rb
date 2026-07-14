require "json"

module Ai
  module PropertySearch
    class Interpreter
      Result = Data.define(:intent, :filters, :missing_required_information, :clarifying_question)

      def initialize(setting:, text:, current_filters: {})
        @setting = setting
        @text = text.to_s.strip
        @current_filters = current_filters
        @contract = FilterContract.new(setting)
      end

      def call
        raise ArgumentError, "Descreva o imóvel que você procura." if @text.blank?

        response = OpenAi::Client.new(api_key: Ai::PropertyContentService.api_key).create_response(payload)
        parsed = JSON.parse(extract_text(response))
        Result.new(
          intent: parsed.fetch("intent"),
          filters: @contract.normalize(parsed.fetch("filters")),
          missing_required_information: Array(parsed["missing_required_information"]).map(&:to_s).first(10),
          clarifying_question: parsed["clarifying_question"].to_s.strip.presence
        )
      end

      private

      def payload
        {
          model: Ai::PropertyContentService.model,
          instructions: instructions,
          input: {
            request: @text,
            current_filters: @current_filters,
            catalog: catalog_context
          }.to_json,
          text: {
            format: {
              type: "json_schema",
              name: "ai_property_search_filters",
              strict: true,
              schema: response_schema
            }
          }
        }
      end

      def instructions
        <<~TEXT
          Você interpreta pedidos de corretores e nunca consulta ou retorna imóveis.
          Sua única função autorizada é preparar filtros para search_properties.
          Não gere SQL, nomes de tabelas, código, credenciais ou campos fora do schema.
          Use português do Brasil em tudo: texto, nomes de filtros, perguntas e valores retornados.
          Normalize termos para pt-BR quando fizer sentido: "apartment" vira "Apartamento", "apartments" vira "Apartamentos" e variações equivalentes devem ser convertidas para a forma usual do mercado imobiliário brasileiro.
          O JSON de contexto do catálogo é sua referência indireta e segura para reconhecer nomes, bairros, cidades, empreendimentos, incorporadoras e características disponíveis no tenant.
          Quando houver current_filters, trate-os como a busca em andamento; se a fala indicar nova busca, ignore o contexto anterior.
          Quando o pedido trouxer uma faixa, interprete como intervalo:
          - "entre R$ 1,5 milhão e R$ 2 milhões" => price_min = 1500000 e price_max = 2000000
          - "de R$ 1,5 milhão até R$ 2 milhões" => price_min = 1500000 e price_max = 2000000
          - "até R$ 2 milhões" => price_max = 2000000
          - "a partir de R$ 1,5 milhão" => price_min = 1500000
          Nunca interrompa a busca com uma pergunta complementar.
          Use somente os filtros identificados e mantenha clarifying_question como null.

          INSTRUÇÕES DA CONTA:
          #{@setting.ai_property_search_instructions}

          PERGUNTAS COMPLEMENTARES ANTES DA BUSCA: desativadas
        TEXT
      end

      def response_schema
        {
          type: "object",
          additionalProperties: false,
          required: %w[intent filters missing_required_information clarifying_question],
          properties: {
            intent: { type: "string", enum: ["search_properties"] },
            filters: @contract.json_schema,
            missing_required_information: { type: "array", items: { type: "string" } },
            clarifying_question: { anyOf: [{ type: "string" }, { type: "null" }] }
          }
        }
      end

      def extract_text(response)
        response["output_text"].presence ||
          Array(response["output"]).flat_map { |item| Array(item["content"]) }.find { |item| item["type"] == "output_text" }&.dig("text") ||
          raise("Resposta da IA sem conteúdo estruturado.")
      end

      def catalog_context
        Ai::PropertySearch::CatalogContext.new(
          setting: @setting,
          tenant: @setting.tenant,
          text: @text,
          current_filters: @current_filters
        ).call
      end
    end
  end
end
