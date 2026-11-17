module Gateway
  module ImovelwebPayload
    class Invalid < StandardError; end
    FIELDS = {
      'event_id' => %w[eventId idEvento], 'event_type' => %w[eventType tipoEvento],
      'client_code' => %w[clientCode codigoImobiliaria codigoInmobiliaria codigoCliente],
      'reference' => %w[reference internalReference referencia clientListingId], 'listing_id' => %w[idNavplat idnavplat originListingId],
      'name' => %w[name nome nombre], 'email' => %w[email], 'phone' => %w[phoneNumber phone telefone telefono],
      'message' => %w[message mensagem mensaje], 'registered_at' => %w[registerDate dataRegistro fechaRegistro timestamp],
      'contact_type' => %w[contactTypeId idTipoContacto], 'message_id' => %w[messageId idMensagem idMensaje],
      'lead_origin' => %w[leadOrigin]
    }.freeze

    def self.diagnostic(payload)
      return {} unless payload.is_a?(Hash)

      { fields: FIELDS.values.flatten.filter_map { |key| [key, payload[key].class.name] if payload.key?(key) }.to_h,
        origin: %w[imovelweb wimoveis imovelweb.com.br wimoveis.com.br].find { |value| value == payload['leadOrigin'].to_s.strip.downcase } }
    end

    def self.normalize(payload)
      raise Invalid, 'object_required' unless payload.is_a?(Hash)
      result = FIELDS.to_h do |field, aliases|
        values = aliases.filter_map do |key|
          value = payload[key]
          raise Invalid, "#{field}:scalar_required" unless value.nil? || value.is_a?(String) || value.is_a?(Integer)
          value.to_s.strip.presence
        end.uniq
        # EN2 can contain split phone plus full phoneNumber; prefer the full number.
        values = [payload['phoneNumber'].to_s.strip] if field == 'phone' && payload['phoneNumber'].present?
        raise Invalid, "#{field}:conflicting_aliases" if values.length > 1
        [field, values.first]
      end.compact
      %w[event_id client_code].each do |key|
        raise Invalid, "#{key}:required_or_too_long" unless result[key].present? && result[key].bytesize <= 255
      end
      raise Invalid, 'event_type:unsupported' unless %w[CONTACTO CONTACTO_MENSAJE].include?(result['event_type'])
      raise Invalid, 'lead_origin:unsupported' if result['lead_origin'].present? && result['lead_origin'].downcase != 'imovelweb'
      result
    end
  end
end
