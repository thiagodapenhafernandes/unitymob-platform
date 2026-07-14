module Ai
  module PropertySearch
    class Transcriber
      ALLOWED_CONTENT_TYPES = %w[audio/webm audio/ogg audio/mp4 audio/mpeg audio/aac audio/x-m4a].freeze
      MAX_BYTES = 15.megabytes

      def initialize(setting:, audio:)
        @setting = setting
        @audio = audio
      end

      def call
        raise ArgumentError, "Envie um arquivo de áudio." unless @audio.respond_to?(:read)
        raise ArgumentError, "Formato de áudio não permitido." unless @audio.content_type.to_s.in?(ALLOWED_CONTENT_TYPES)
        raise ArgumentError, "O áudio ultrapassa o limite de 15 MB." if @audio.size.to_i > MAX_BYTES
        raise ArgumentError, "Busca por voz desativada para esta conta." unless @setting.voice_property_search_enabled?

        OpenAi::Client.new(api_key: Ai::PropertyContentService.api_key).transcribe(
          file: @audio,
          language: @setting.ai_property_search_language,
          prompt: vocabulary_prompt
        )
      end

      private

      def vocabulary_prompt
        return nil unless @setting.respond_to?(:ai_property_search_transcription_vocabulary_enabled?)
        return nil unless @setting.ai_property_search_transcription_vocabulary_enabled?

        TranscriptionVocabulary.new(tenant: @setting.tenant, setting: @setting).call
      rescue StandardError => e
        Rails.logger.warn("[ai property search vocabulary] #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
