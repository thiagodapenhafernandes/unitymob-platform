module Ai
  class PropertyTextFormatter
    FINAL_PHRASES = [
      "Não perca a oportunidade de viver em um dos destinos mais desejados de Santa Catarina!",
      "O valor do aluguel já contempla todas as taxas, garantindo mais praticidade e comodidade para você. Sem surpresas no final do mês, apenas o valor anunciado!",
      "A Salute Imóveis está localizada em Balneário Camboriú, Santa Catarina.",
      "O seu DNA é o atendimento diferenciado para quem quer comprar ou vender um imóvel. Fale com a gente em um dos nossos canais de atendimento ou venha nos fazer uma visita.",
      "Os valores estão sujeitos a alteração sem aviso prévio."
    ].freeze

    def self.call(text)
      new(text).call
    end

    def initialize(text)
      @text = text.to_s
    end

    def call
      normalized = @text.gsub(/[[:space:]]+/, " ").strip
      return normalized if normalized.blank?

      body, endings = extract_final_phrases(normalized)
      paragraphs = body_paragraphs(body)
      paragraphs.concat(endings)
      paragraphs.reject(&:blank?).join("\n\n")
    end

    private

    def extract_final_phrases(text)
      body = text.dup
      endings = []

      FINAL_PHRASES.each do |phrase|
        next unless body.include?(phrase)

        body = body.sub(phrase, "").strip
        endings << phrase
      end

      [body, endings]
    end

    def body_paragraphs(text)
      sentences = text.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:blank?)
      return [text] if sentences.size <= 2

      sentences.each_slice(3).map { |slice| slice.join(" ") }
    end
  end
end
