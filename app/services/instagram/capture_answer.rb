module Instagram
  # Extração conservadora: perguntas e descrições de imóveis não são nomes.
  class CaptureAnswer
    def self.complete?(lead)
      new(lead.client_name).name.present? && new(lead.display_phone).phone.present?
    end

    def initialize(text)
      @text = text.to_s.squish
    end

    def name(explicit_only: false)
      return if declined?
      explicit = @text.match(/\b(?:me chamo|meu nome [ée]|pode me chamar de|sou(?: (?:o|a))?)\s+([^,;.!?\d]+)/i)
      return if explicit_only && !explicit
      plain_name = @text.sub(/[\s,;:]+\(?\+?\d[\d() .-]{8,}\d\)?\z/, '')
      value = (explicit ? explicit[1] : plain_name).split(/\s+e\s+(?:meu|minha|o|a)\s+(?:telefone|whats)/i).first.to_s.strip
      return unless value.match?(/\A[\p{L}\p{M}][\p{L}\p{M} ’'-]{1,59}\z/) && value.split.size <= 5
      return if value.match?(/\b(?:oi|ol[áa]|bom dia|boa tarde|boa noite|obrigad[oa]|sim|n[aã]o|sobre|quero|gostaria|preciso|tenho|pode|qual|como|onde|quanto|apto|apartamento|im[oó]vel|casa|an[uú]ncio|pagamento|financia\w*|valor|pre[cç]o|shopping|telefone|whatsapp|interesse|busco|procuro|centro|bairro|c[oó]digo|refer[eê]ncia|atendente|corretor|humano|pular|manda|mande|envie|envia|mostra|mostre|saber|me|fotos|informa[cç][oõ]es|condi[cç][oõ]es|aceita|entrada|estou|gostei|vamos|achei|entendi)\b/i)

      value
    end

    def phone
      return if @text.match?(/R\$|\b(?:pre[cç]o|valor|reais)\b/i)
      candidate = @text[/\+?\d[\d() .-]{8,}\d/]
      return unless candidate
      return unless @text.match?(/\A[\d() .+-]+\z/) || @text.match?(/\b(?:telefone|celular|whats(?:app)?|n[uú]mero|contato|me liga|me chama)\b/i) || name.present?
      digits = candidate.gsub(/\D/, '')
      return unless candidate.start_with?('+') || digits.length.in?([10, 11]) || (digits.start_with?('55') && digits.length.in?([12, 13]))

      normalized = Phones::Normalizer.call(candidate)
      normalized if normalized && Phonelib.parse("+#{normalized}").valid?
    end

    def request?
      name.nil? && phone.nil? && !declined? && @text.match?(/\?|quero|gostaria|sobre|im[oó]vel|apartamento|apto|pagamento|financ|c[oó]digo|link|corretor|atendente/i)
    end

    def declined?
      @text.match?(/\b(?:prefiro (?:por )?aqui|continuar (?:por )?aqui|n[aã]o (?:quero|vou|posso) (?:informar|passar|dar)|sem (?:telefone|whatsapp)|pular)\b/i)
    end
  end
end
