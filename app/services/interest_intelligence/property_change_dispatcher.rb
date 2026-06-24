module InterestIntelligence
  class PropertyChangeDispatcher
    def self.price_drop(habitation)
      new(habitation).price_drop
    end

    def initialize(habitation)
      @habitation = habitation
      @settings = InterestIntelligence::Settings.current
    end

    def price_drop
      return unless @settings.enabled?
      return unless price_dropped?

      ClientPropertyInterest
        .where(habitation_id: @habitation.id)
        .where.not(lead_id: nil)
        .includes(:matched_lead)
        .find_each do |interest|
          lead = interest.matched_lead
          next unless lead

          Automation::Dispatcher.dispatch(
            :interested_property_price_dropped,
            lead,
            source: "interest_intelligence",
            payload: {
              habitation_id: @habitation.id,
              codigo: @habitation.codigo,
              title: @habitation.display_title,
              old_price_cents: previous_price_cents,
              new_price_cents: current_price_cents
            },
            idempotency_key: "interested_property_price_dropped:lead:#{lead.id}:habitation:#{@habitation.id}:#{current_price_cents}"
          )
        end
    rescue => e
      Rails.logger.warn("[interest price drop] #{e.class}: #{e.message}")
    end

    private

    def price_dropped?
      previous_price_cents.to_i.positive? &&
        current_price_cents.to_i.positive? &&
        current_price_cents.to_i < previous_price_cents.to_i
    end

    def previous_price_cents
      @previous_price_cents ||= begin
        sale = previous_value(:valor_venda_cents)
        rent = previous_value(:valor_locacao_cents)
        sale.to_i.positive? ? sale : rent
      end
    end

    def current_price_cents
      @current_price_cents ||= @habitation.valor_venda_cents.to_i.positive? ? @habitation.valor_venda_cents : @habitation.valor_locacao_cents
    end

    def previous_value(attribute)
      change = @habitation.saved_change_to_attribute(attribute)
      change ? change.first : @habitation.public_send(attribute)
    end
  end
end
