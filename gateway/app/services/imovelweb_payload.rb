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

    def self.normalize(payload)
      raise Invalid unless payload.is_a?(Hash)
      result = FIELDS.to_h do |field, aliases|
        values = aliases.filter_map do |key|
          value = payload[key]
          raise Invalid unless value.nil? || value.is_a?(String) || value.is_a?(Integer)
          value.to_s.strip.presence
        end.uniq
        # EN2 can contain split phone plus full phoneNumber; prefer the full number.
        values = [payload['phoneNumber'].to_s.strip] if field == 'phone' && payload['phoneNumber'].present?
        raise Invalid if values.length > 1
        [field, values.first]
      end.compact
      raise Invalid unless %w[event_id client_code].all? { |key| result[key].present? && result[key].bytesize <= 255 }
      raise Invalid unless %w[CONTACTO CONTACTO_MENSAJE].include?(result['event_type'])
      raise Invalid if result['lead_origin'].present? && result['lead_origin'].downcase != 'imovelweb'
      result
    end
  end
end
