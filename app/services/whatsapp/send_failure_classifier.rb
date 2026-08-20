module Whatsapp
  class SendFailureClassifier
    SERVICE_WINDOW_CODES = %w[131047 470].freeze
    SERVICE_WINDOW_PATTERNS = [
      /re-?engagement/i,
      /24.?hour/i,
      /customer service window/i,
      /outside.*service window/i,
      /janela.*atendimento/i
    ].freeze

    class << self
      def service_window_closed?(error_message: nil, meta_error: nil)
        new(error_message:, meta_error:).service_window_closed?
      end

      def message_from_result(result)
        error_message = result[:error].to_s
        code = meta_code(result[:meta_error])
        [code.present? ? "##{code}" : nil, error_message.presence].compact.join(" ")
          .presence || "Falha informada pela Meta"
      end

      def message_from_status_error(error)
        return if error.blank?

        code = error["code"].presence || error[:code].presence
        title = error["title"].presence || error[:title].presence
        message = error["message"].presence || error[:message].presence
        details = error.dig("error_data", "details") if error.respond_to?(:dig)
        details ||= error.dig(:error_data, :details) if error.respond_to?(:dig)

        parts = []
        parts << [code.present? ? "##{code}" : nil, title].compact.join(" ").presence
        parts << message
        parts << details
        parts.compact_blank.uniq.join(" - ").presence
      end

      private

      def meta_code(meta_error)
        return if meta_error.blank?

        meta_error[:code].presence || meta_error["code"].presence
      end
    end

    def initialize(error_message: nil, meta_error: nil)
      @error_message = error_message.to_s
      @meta_error = meta_error || {}
    end

    def service_window_closed?
      SERVICE_WINDOW_CODES.include?(meta_code.to_s) ||
        SERVICE_WINDOW_CODES.any? { |code| error_message.include?("##{code}") } ||
        SERVICE_WINDOW_PATTERNS.any? { |pattern| error_message.match?(pattern) }
    end

    private

    attr_reader :error_message, :meta_error

    def meta_code
      meta_error[:code].presence || meta_error["code"].presence
    end
  end
end
