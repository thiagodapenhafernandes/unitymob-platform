module Instagram
  class PropertyContext
    attr_reader :unavailable

    def initialize(lead, rule = {})
      @lead, @tenant, @rule = lead, lead.tenant, rule
    end

    def resolve(messages)
      scope = @tenant.habitations.public_property_listable
      latest = messages.reverse.find { |message| message[:role] == "cliente" }&.fetch(:text, "").to_s
      messages.reverse_each do |message|
        text = message[:text].to_s
        linked = PropertyJourney.properties_in(@tenant, text)
        if linked.any?
          ordinal = latest[/primeir[oa]|segund[oa]|terceir[oa]/i]&.downcase
          index = {"primeiro" => 0, "primeira" => 0, "segundo" => 1, "segunda" => 1, "terceiro" => 2, "terceira" => 2}[ordinal]
          return linked[index] if index
          return linked.one? ? linked.first : nil
        end
        next unless message[:role] == "cliente"
        codes = InstagramMessage.property_codes_in(text)
        return codes.one? ? find_reference(scope, codes.first) : nil if codes.any?
        # Uma nova busca encerra a referência antiga, inclusive nas respostas seguintes.
        return nil if text.match?(CatalogReply::NEW_SEARCH) && !text.match?(/\b(?:esse|essa|este|esta)\b/i)
      end
      # Captions are read in full, independently of the short conversation sent to the model.
      @lead.instagram_messages.inbound.order(id: :desc).limit(50).each do |message|
        codes = message.property_reference_codes
        codes = [message.context["property_code"]] if codes.empty? && message.context["property_code"].present?
        return codes.one? ? find_reference(scope, codes.first) : nil if codes.any?
      end
      stored = @lead.instagram_messages.inbound.where("context ? 'property_code'").order(id: :desc).first
      return find_reference(scope, stored.context["property_code"]) if stored
      return find_reference(scope, @rule["property_code"]) if @rule["property_code"].present?
      scope.find_by(id: @lead.property_id) if @lead.property_id.present?
    end

    private

    def find_reference(scope, code)
      property = scope.find_by(codigo: code)
      @unavailable = property.nil?
      property
    end

  end
end
