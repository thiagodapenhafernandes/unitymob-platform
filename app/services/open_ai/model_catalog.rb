require "digest"
require "json"
require "net/http"
require "set"
require "uri"

module OpenAi
  class ModelCatalog
    MODELS_URL = "https://api.openai.com/v1/models".freeze
    AUTOMATIC_VALUE = "__automatic__".freeze
    CUSTOM_VALUE = "__custom__".freeze
    CACHE_TTL = 12.hours

    RESPONSE_FALLBACK_MODEL = Ai::PropertyContentService::DEFAULT_MODEL
    TRANSCRIPTION_FALLBACK_MODEL = Ai::PropertySearch::Configuration::DEFAULT_TRANSCRIPTION_MODEL

    CURATED_RESPONSE_MODELS = [
      ["Automático recomendado", AUTOMATIC_VALUE],
      ["GPT-4.1 mini · rápido e econômico", "gpt-4.1-mini"],
      ["GPT-4.1 · mais capacidade", "gpt-4.1"],
      ["GPT-4o mini · compatibilidade", "gpt-4o-mini"],
      ["GPT-4o · compatibilidade", "gpt-4o"]
    ].freeze

    CURATED_TRANSCRIPTION_MODELS = [
      ["Automático recomendado", AUTOMATIC_VALUE],
      ["GPT-4o mini transcribe · padrão atual", "gpt-4o-mini-transcribe"],
      ["GPT-4o transcribe", "gpt-4o-transcribe"],
      ["GPT transcribe", "gpt-transcribe"],
      ["Whisper 1 · compatibilidade", "whisper-1"]
    ].freeze

    class << self
      def response_model_options(api_key: nil, selected: nil)
        model_options(
          curated: CURATED_RESPONSE_MODELS,
          available_ids: response_model_ids(api_key:),
          selected:
        )
      end

      def transcription_model_options(api_key: nil, selected: nil)
        model_options(
          curated: CURATED_TRANSCRIPTION_MODELS,
          available_ids: transcription_model_ids(api_key:),
          selected:
        )
      end

      def resolve_response_model(value)
        model = value.to_s.strip
        return RESPONSE_FALLBACK_MODEL if model.blank? || model == AUTOMATIC_VALUE

        model
      end

      def resolve_transcription_model(value)
        model = value.to_s.strip
        return TRANSCRIPTION_FALLBACK_MODEL if model.blank? || model == AUTOMATIC_VALUE

        model
      end

      def fallback_response_model(configured_model = nil)
        configured_model.to_s.strip == RESPONSE_FALLBACK_MODEL ? nil : RESPONSE_FALLBACK_MODEL
      end

      def fallback_transcription_model(configured_model = nil)
        configured_model.to_s.strip == TRANSCRIPTION_FALLBACK_MODEL ? nil : TRANSCRIPTION_FALLBACK_MODEL
      end

      def known_response_model?(model)
        known_model?(model, CURATED_RESPONSE_MODELS)
      end

      def known_transcription_model?(model)
        known_model?(model, CURATED_TRANSCRIPTION_MODELS)
      end

      def automatic?(value)
        value.to_s.strip == AUTOMATIC_VALUE
      end

      def custom?(value)
        value.to_s.strip == CUSTOM_VALUE
      end

      private

      def model_options(curated:, available_ids:, selected:)
        options = curated.dup
        curated_values = options.map(&:second).to_set

        available_ids.each do |model_id|
          next if curated_values.include?(model_id)

          options << [model_id, model_id]
        end

        selected_model = selected.to_s.strip
        if selected_model.present? && selected_model != CUSTOM_VALUE && options.none? { |_label, value| value == selected_model }
          options << ["Atual: #{selected_model}", selected_model]
        end

        options << ["Personalizado", CUSTOM_VALUE]
      end

      def response_model_ids(api_key:)
        available_model_ids(api_key:).select do |model_id|
          model_id.start_with?("gpt-") &&
            !model_id.match?(/transcribe|tts|realtime|audio|image|embedding|moderation/i)
        end
      end

      def transcription_model_ids(api_key:)
        available_model_ids(api_key:).select do |model_id|
          model_id.match?(/transcribe/i) || model_id == "whisper-1"
        end
      end

      def available_model_ids(api_key:)
        token = api_key.to_s.strip
        return [] if token.blank?

        Rails.cache.fetch(["openai-model-catalog", Digest::SHA256.hexdigest(token)], expires_in: CACHE_TTL) do
          fetch_model_ids(token)
        end
      rescue StandardError => e
        Rails.logger.info("[openai model catalog] #{e.class}: #{e.message}")
        []
      end

      def fetch_model_ids(api_key)
        uri = URI.parse(MODELS_URL)
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{api_key}"

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 8, open_timeout: 4) do |http|
          http.request(request)
        end
        return [] unless response.is_a?(Net::HTTPSuccess)

        parsed = JSON.parse(response.body) rescue {}
        Array(parsed["data"]).filter_map { |item| item["id"].to_s.presence }.sort
      end

      def known_model?(model, catalog)
        value = model.to_s.strip
        return true if value.blank? || value == AUTOMATIC_VALUE

        catalog.any? { |_label, option_value| option_value == value }
      end
    end
  end
end
