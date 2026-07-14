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

    def create_response(payload)
      raise "Token da OpenAI não configurado." if @api_key.blank?

      uri = URI.parse(API_URL)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      request.body = payload.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 90, open_timeout: 15) do |http|
        http.request(request)
      end

      parsed = JSON.parse(response.body) rescue {}
      unless response.is_a?(Net::HTTPSuccess)
        message = parsed.dig("error", "message").presence || response.message
        raise "OpenAI retornou erro #{response.code}: #{message}"
      end

      parsed
    end

    def transcribe(file:, language:, model: "gpt-4o-mini-transcribe", prompt: nil)
      raise "Token da OpenAI não configurado." if @api_key.blank?

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
      parsed = JSON.parse(response.body) rescue {}
      unless response.is_a?(Net::HTTPSuccess)
        message = parsed.dig("error", "message").presence || response.message
        raise "OpenAI retornou erro #{response.code}: #{message}"
      end

      parsed.fetch("text").to_s.strip
    end

    private

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
