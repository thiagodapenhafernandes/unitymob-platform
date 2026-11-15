module Instagram
  # Guarda o pedido do cliente como evidência, sem transformar legenda ou reação em intenção.
  class Qualification
    KEY = 'instagram_qualification'.freeze
    NEXT_STEP = /\b(?:visitar|visita|conhecer|agendar|falar com (?:um |o )?corretor|receber (?:mais |outras )?op[cç][oõ]es|quero (?:esse|este)|tenho interesse)\b/i
    CRITERIA = /\b(?:at[eé]\s+(?:R\$\s*)?\d|\d+\s*(?:mil|milh[oõ]es|quartos|su[ií]tes)|(?:alugar|comprar|procuro|busco).{0,60}\b(?:no|na|em)\s+[\p{L}]{3,})/i
    NEGATIVE = /\b(?:n[aã]o (?:quero|tenho interesse|pretendo)|sem interesse|s[oó] (?:olhando|curiosidade)|talvez)\b/i
    OWNER = /\b(?:quero|preciso|pretendo|gostaria de)\s+(?:vender|anunciar|colocar.{0,20}(?:venda|aluguel))\b/i

    def self.capture!(lead, rule: CaptureSettings.defaults)
      messages = lead.instagram_messages.inbound.order(id: :desc).limit(30).to_a.reverse
      texts = messages.filter_map { |m| m.body.presence }
      latest = texts.last.to_s
      previous = lead.other_information.to_h[KEY].to_h
      return previous if latest.blank?
      actionable = messages.select { |m| m.body.present? && !m.body.match?(NEGATIVE) && !m.body.match?(OWNER) }
      mode_message = actionable.reverse.find { |m| CaptureAnswer.new(m.body).business_type.present? }
      mode = mode_message && CaptureAnswer.new(mode_message.body).business_type
      history = lead.instagram_messages.order(id: :desc).limit(30).to_a.reverse.map do |message|
        {role: message.inbound? ? 'cliente' : 'assistente', text: message.conversation_text}
      end
      property = PropertyContext.new(lead, rule).resolve(history)
      step_message = actionable.reverse.find { |m| m.body.match?(NEXT_STEP) }
      criteria_message = actionable.reverse.find { |m| m.body.match?(CRITERIA) && !m.body.include?('?') }
      step_message = nil if criteria_message && step_message && step_message.id < criteria_message.id
      property = nil if mode == 'venda' && property&.status == 'Aluguel' || mode == 'locacao' && property&.status == 'Venda'
      request = criteria_message || step_message || mode_message
      mode ||= {'Venda' => 'venda', 'Aluguel' => 'locacao'}[property&.status] if step_message
      ready = %w[venda locacao].include?(mode) && (property && step_message || criteria_message)
      last_owner = messages.reverse.find { |message| message.body.to_s.match?(OWNER) }
      owner_request = last_owner && (!mode_message || last_owner.id >= mode_message.id)
      last_negative = messages.reverse.find { |message| message.body.to_s.match?(NEGATIVE) }
      evidence_id = [mode_message, criteria_message, step_message].compact.map(&:id).max.to_i
      ready = false if owner_request || last_negative && last_negative.id >= evidence_id
      data = {
        'ready' => !!ready, 'business_type' => mode, 'property_id' => property&.id,
        'property_code' => property&.codigo, 'request' => clean(request&.body),
        'next_step' => step_message ? clean(step_message.body) : (ready ? 'Receber opções compatíveis com a busca' : nil),
        'message_id' => messages.last&.id
      }.compact
      lead.update_columns(other_information: lead.other_information.to_h.merge(KEY => data))
      data
    end

    def self.clean(text)
      text.to_s.squish.gsub(/[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}/, '[e-mail]')
        .gsub(/\+?\d[\d ().-]{8,}\d/, '[telefone]').first(400).presence
    end

    def self.summary(lead)
      data = lead.other_information.to_h[KEY].to_h
      return if data.blank? || data['ready'] != true
      property = lead.tenant.habitations.public_property_listable.find_by(id: data['property_id']) if data['property_id']
      parts = ["Qualificação pelo Instagram — #{ {'venda'=>'Venda', 'locacao'=>'Locação'}[data['business_type']] }"]
      parts << "Imóvel #{property.codigo}: #{property.display_title}" if property
      parts << "Pedido: #{data['request']}" if data['request'].present?
      parts << "Próximo passo: #{data['next_step']}" if data['next_step'].present?
      parts.join(' · ').first(850)
    end
  end
end
