module Ai
  module PropertySearch
    # Busca por descrição (texto ou voz) feita pelo visitante do site: interpreta com a mesma IA da busca interna e devolve
    # os filtros no vocabulário da listagem pública. Nunca devolve imóveis nem grava histórico: o site navega para a listagem
    # normal com esses filtros. O áudio só é enviado para transcrição e não é guardado.
    class PublicQuery
      Result = Data.define(:params, :summary, :transcription)

      class Unavailable < StandardError; end

      MAX_TEXT = 300
      MAX_AUDIO_SECONDS = 30

      def self.available?(tenant:)
        setting = setting_for(tenant)
        setting.present? && setting.ai_property_search_enabled? && Configuration.connected?(tenant: tenant)
      end

      def self.voice_available?(tenant:)
        available?(tenant: tenant) && setting_for(tenant).voice_property_search_enabled?
      end

      # find_by (e não .instance): uma visita pública nunca cria configuração.
      def self.setting_for(tenant)
        tenant && PropertySetting.find_by(tenant_id: tenant.id)
      end

      def initialize(tenant:, text: nil, audio: nil, audio_duration: nil, default_transaction: nil)
        @tenant = tenant
        @text = text.to_s.squish.first(MAX_TEXT)
        @audio = audio
        @audio_duration = Float(audio_duration, exception: false)
        @default_transaction = default_transaction
      end

      def call
        raise Unavailable, "Busca por descrição indisponível." unless self.class.available?(tenant: @tenant)

        setting = self.class.setting_for(@tenant)
        text = @audio.present? ? transcribe(setting) : @text
        raise ArgumentError, "Descreva o imóvel que você procura." if text.blank?

        interpretation = Interpreter.new(setting: setting, text: text).call
        filters = LocationResolver.new(tenant: @tenant, setting: setting, filters: interpretation.filters).call.filters
        params = PublicParams.new(filters, default_transaction: @default_transaction).call
        raise ArgumentError, "Não consegui entender o que você procura. Tente citar o tipo, a região ou o valor." if params.except("transaction_type").empty?

        Result.new(params: params, summary: PublicParams.summary(filters), transcription: text)
      end

      private

      def transcribe(setting)
        raise Unavailable, "Busca por voz indisponível." unless self.class.voice_available?(tenant: @tenant)
        raise ArgumentError, "Não foi possível validar a duração do áudio." unless @audio_duration
        raise ArgumentError, "O áudio ultrapassa #{MAX_AUDIO_SECONDS} segundos." if @audio_duration > MAX_AUDIO_SECONDS

        text = Transcriber.new(setting: setting, audio: @audio).call.to_s.squish.first(MAX_TEXT)
        raise ArgumentError, "Não consegui entender o áudio. Fale a descrição do imóvel e tente de novo." if text.blank?

        text
      end
    end
  end
end
