require "json"
require "net/http"
require "open3"
require "securerandom"
require "tempfile"
require "uri"

module MetaAi
  # Cliente da Meta Model API (https://api.meta.ai/v1), mesma interface de
  # OpenAi::Client para permitir a troca de provedor por conta.
  #
  # Contratos (https://dev.meta.ai/docs):
  # - Responses API compatível com o SDK OpenAI (mesmo payload);
  # - transcrição em /v1/asr/transcribe (multipart request+audio), resposta
  #   com "transcript", áudio exigido em WAV mono 16-bit 16/24 kHz.
  class Client
    RESPONSES_URL = "https://api.meta.ai/v1/responses".freeze
    TRANSCRIBE_URL = "https://api.meta.ai/v1/asr/transcribe".freeze
    DEFAULT_TRANSCRIPTION_MODEL = ModelCatalog::DEFAULT_TRANSCRIPTION_MODEL

    # BCP-47 parcial -> rótulo de idioma do languageBias (demais: autodetect).
    LANGUAGE_BIAS = {
      "pt" => "Portuguese",
      "en" => "English",
      "es" => "Spanish"
    }.freeze

    def initialize(api_key:)
      @api_key = api_key.to_s
    end

    def create_response(payload, fallback_model: nil)
      attempts = [payload[:model].presence || payload["model"].presence, fallback_model].compact.uniq
      attempts = [nil] if attempts.empty?

      attempts.each_with_index do |model, index|
        request_payload = model ? payload.merge(model: model) : payload
        response = post_json(RESPONSES_URL, request_payload)
        return parse_success(response) if response.is_a?(Net::HTTPSuccess)
        raise response_error(response) unless model_retryable_error?(response) && index < attempts.size - 1
      end
    end

    def transcribe(file:, language:, model: DEFAULT_TRANSCRIPTION_MODEL, prompt: nil, keywords: nil, fallback_model: nil)
      wav_path = convert_to_wav!(file)
      attempts = [model.presence, fallback_model].compact.uniq

      attempts.each_with_index do |attempt_model, index|
        response = post_transcription(wav_path, attempt_model, language: language, keywords: keywords)
        return parse_transcription(response) if response.is_a?(Net::HTTPSuccess)
        raise response_error(response) unless model_retryable_error?(response) && index < attempts.size - 1
      end
    ensure
      File.delete(wav_path) if wav_path && File.exist?(wav_path)
    end

    private

    def post_json(url, payload)
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      request.body = payload.to_json

      Rails.logger.info("[meta muse client] POST #{uri.path} model=#{payload[:model] || payload['model']}")
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 120) do |http|
        http.request(request)
      end
    end

    def post_transcription(wav_path, model, language:, keywords:)
      uri = URI.parse("#{TRANSCRIBE_URL}?sessionId=#{SecureRandom.uuid}")
      settings = {
        mode: "PUSH_TO_TALK",
        model: model,
        audioEncoding: "WAV",
        languageBias: language_bias(language),
        keywords: Array(keywords).map(&:to_s).reject(&:blank?).presence
      }.compact

      boundary = "----UnitymobMeta#{SecureRandom.hex(16)}"
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      request.body = transcribe_multipart_body(boundary: boundary, settings: settings, wav_path: wav_path)

      Rails.logger.info("[meta muse client] POST #{uri.path} model=#{model}")
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 120) do |http|
        http.request(request)
      end
    end

    def transcribe_multipart_body(boundary:, settings:, wav_path:)
      parts = []
      parts << "--#{boundary}\r\n" \
        "Content-Disposition: form-data; name=\"request\"\r\n" \
        "Content-Type: application/json\r\n\r\n" \
        "#{settings.to_json}\r\n"
      parts << "--#{boundary}\r\n" \
        "Content-Disposition: form-data; name=\"audio\"; filename=\"audio.wav\"\r\n" \
        "Content-Type: audio/wav\r\n\r\n" \
        "#{File.binread(wav_path)}\r\n"
      parts << "--#{boundary}--\r\n"
      parts.join.b
    end

    def convert_to_wav!(file)
      unless Whatsapp::MediaConverter.available?
        raise "Transcrição Meta Muse indisponível: este formato precisa de conversão e o ffmpeg não está disponível no servidor."
      end

      input_path = file.respond_to?(:path) ? file.path.to_s : file.to_s
      output = Tempfile.new(["meta-stt", ".wav"])
      output_path = output.path
      output.close

      _out, err, status = Open3.capture3(
        Whatsapp::MediaConverter.ffmpeg_bin, "-y", "-i", input_path,
        "-ac", "1", "-ar", "24000", "-c:a", "pcm_s16le", output_path
      )
      raise "Meta Muse retornou erro de áudio: #{err.to_s.lines.first(3).join(' ').squish.presence || 'falha na conversão'}" unless status.success?

      output_path
    end

    def language_bias(language)
      label = LANGUAGE_BIAS[language.to_s.split("-").first.to_s.downcase]
      label ? [label] : nil
    end

    def parse_success(response)
      JSON.parse(response.body)
    rescue JSON::ParserError
      raise "Meta Muse retornou resposta inválida (HTTP #{response.code})."
    end

    def parse_transcription(response)
      parsed = parse_success(response)
      transcript = parsed["transcript"].to_s.strip
      raise "Meta Muse retornou transcrição vazia." if transcript.blank?

      transcript
    end

    def response_error(response)
      message = parsed_error_message(response)
      detail = [response.code, response.message, message].reject(&:blank?).join(" ").squish
      RuntimeError.new("Meta Muse retornou erro #{detail.presence || 'desconhecido'}.")
    end

    def parsed_error_message(response)
      parsed = JSON.parse(response.body) rescue {}
      parsed.dig("error", "message").to_s.presence
    end

    def model_retryable_error?(response)
      return false unless %w[400 403 404].include?(response.code.to_s)

      message = parsed_error_message(response).downcase
      message.include?("model") && (
        message.include?("not exist") || message.include?("not found") ||
        message.include?("unknown") || message.include?("unavailable") ||
        message.include?("access") || message.include?("permission")
      )
    end
  end
end
