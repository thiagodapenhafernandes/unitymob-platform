require "json"
require "net/http"
require "uri"

module OpenAi
  class Client
    API_URL = "https://api.openai.com/v1/responses".freeze
    TRANSCRIPTION_URL = "https://api.openai.com/v1/audio/transcriptions".freeze

    def initialize(api_key:)
      @api_key = api_key.to_s.strip
    end

    def create_response(payload, fallback_model: nil)
      raise "Token da OpenAI não configurado." if @api_key.blank?

      request_payload = payload.deep_dup
      response, parsed = perform_json_request(API_URL, request_payload)
      if response.is_a?(Net::HTTPSuccess)
        return parsed
      end

      fallback_payload = fallback_payload_for(request_payload, fallback_model)
      if fallback_payload && model_retryable_error?(response, parsed)
        Rails.logger.info("[openai client] retrying with fallback model #{fallback_payload[:model] || fallback_payload['model']}")
        response, parsed = perform_json_request(API_URL, fallback_payload)
        return parsed if response.is_a?(Net::HTTPSuccess)
      end

      raise_response_error!(response, parsed)
    end

    def transcribe(file:, language:, model: "gpt-4o-mini-transcribe", prompt: nil, fallback_model: nil)
      raise "Token da OpenAI não configurado." if @api_key.blank?

      response, parsed = perform_transcription_request(file:, language:, model:, prompt:)
      return parsed.fetch("text").to_s.strip if response.is_a?(Net::HTTPSuccess)

      fallback = fallback_model.to_s.strip
      if fallback.present? && fallback != model.to_s.strip && model_retryable_error?(response, parsed)
        Rails.logger.info("[openai client] retrying transcription with fallback model #{fallback}")
        response, parsed = perform_transcription_request(file:, language:, model: fallback, prompt:)
        return parsed.fetch("text").to_s.strip if response.is_a?(Net::HTTPSuccess)
      end

      raise_response_error!(response, parsed)
    end

    private

    def perform_json_request(url, payload)
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      request.body = payload.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 90, open_timeout: 15) do |http|
        http.request(request)
      end

      [response, JSON.parse(response.body)]
    rescue JSON::ParserError
      [response, {}]
    end

    def perform_transcription_request(file:, language:, model:, prompt:)
      fields = { model: model, language: language.to_s.split("-").first }
      fields[:prompt] = prompt if prompt.present?
      boundary = "----Unitymob#{SecureRandom.hex(16)}"
      body = multipart_body(
        boundary: boundary,
        fields: fields,
        file: file
      )
      uri = URI.parse(TRANSCRIPTION_URL)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      request.body = body

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 120, open_timeout: 15) do |http|
        http.request(request)
      end

      [response, JSON.parse(response.body)]
    rescue JSON::ParserError
      [response, {}]
    end

    def fallback_payload_for(payload, fallback_model)
      fallback = fallback_model.to_s.strip
      current = payload[:model].presence || payload["model"].presence
      return nil if fallback.blank? || current.to_s.strip == fallback

      fallback_payload = payload.deep_dup
      fallback_payload.delete(:model)
      fallback_payload.delete("model")
      fallback_payload[:model] = fallback
      fallback_payload
    end

    def model_retryable_error?(response, parsed)
      return false unless response.code.to_i.in?([400, 403, 404])

      message = parsed.dig("error", "message").to_s
      code = parsed.dig("error", "code").to_s
      type = parsed.dig("error", "type").to_s
      [message, code, type].join(" ").match?(/model|does not exist|not found|permission|access|unsupported/i)
    end

    def raise_response_error!(response, parsed)
      message = parsed.dig("error", "message").presence || response.message
      raise "OpenAI retornou erro #{response.code}: #{message}"
    end

    def multipart_body(boundary:, fields:, file:)
      # Corpo em binário: campos UTF-8 com acentos (ex.: prompt de vocabulário)
      # não podem ser concatenados ao file.read (ASCII-8BIT) numa string UTF-8.
      body = (+"").b
      fields.each do |name, value|
        body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n".b
      end
      body << "--#{boundary}\r\n".b
      body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{File.basename(file.original_filename.to_s)}\"\r\n".b
      body << "Content-Type: #{file.content_type.presence || 'application/octet-stream'}\r\n\r\n".b
      body << file.read.to_s.b
      body << "\r\n--#{boundary}--\r\n".b
      file.rewind
      body
    end
  end
end
