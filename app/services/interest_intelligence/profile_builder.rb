module InterestIntelligence
  class ProfileBuilder
    def self.call(lead)
      new(lead).call
    end

    def initialize(lead)
      @lead = lead
    end

    def call
      {
        lead_id: @lead.id,
        generated_at: Time.current.iso8601,
        criteria: criteria,
        confidence: confidence,
        signals: signal_summary,
        property_ids: property_ids
      }
    end

    private

    def criteria
      {
        cities: top_values(:city),
        neighborhoods: top_values(:neighborhood),
        categories: top_values(:category),
        bedrooms: dominant_number(:bedrooms),
        parking_spaces: dominant_number(:parking_spaces),
        min_price_cents: price_range.first,
        max_price_cents: price_range.last
      }.compact
    end

    def confidence
      score = 0
      score += 25 if top_values(:city).any?
      score += 20 if top_values(:category).any?
      score += 20 if price_range.compact.any?
      score += 15 if dominant_number(:bedrooms).present?
      score += 5 if dominant_number(:parking_spaces).present?
      score += [property_events.count * 5, 20].min
      [score, 100].min
    end

    def signal_summary
      {
        navigation_events: events.count,
        property_views: property_events.count,
        searches: search_events.count,
        explicit_interests: explicit_interests.count,
        total_duration_seconds: events.sum(:duration_seconds).to_i,
        repeated_property_views: repeated_property_views
      }
    end

    def top_values(attribute)
      values = property_snapshots.filter_map { |snapshot| snapshot.with_indifferent_access[attribute].presence }
      values += search_values(attribute)
      values.tally.sort_by { |_value, count| -count }.map(&:first).first(5)
    end

    def dominant_number(attribute)
      values = property_snapshots.filter_map { |snapshot| snapshot.with_indifferent_access[attribute].presence&.to_i }.reject(&:zero?)
      values.tally.max_by { |_value, count| count }&.first
    end

    def price_range
      prices = property_snapshots.filter_map { |snapshot| snapshot.with_indifferent_access[:price_cents].presence&.to_i }.reject(&:zero?)
      return [nil, nil] if prices.blank?

      [prices.min, prices.max]
    end

    def property_ids
      ids = property_events.where.not(habitation_id: nil).pluck(:habitation_id)
      ids << @lead.property_id if @lead.respond_to?(:property_id) && @lead.property_id.present?
      ids.compact.uniq
    end

    def property_snapshots
      @property_snapshots ||= begin
        snapshots = property_events.map { |event| event.property_snapshot.to_h }
        explicit_interests.includes(:habitation).filter_map { |interest| snapshot_for(interest.habitation) } + snapshots
      end
    end

    def snapshot_for(habitation)
      return nil unless habitation

      {
        "city" => habitation_location(habitation, :cidade),
        "neighborhood" => habitation_location(habitation, :bairro),
        "category" => habitation.categoria,
        "bedrooms" => habitation.dormitorios_qtd,
        "parking_spaces" => habitation.vagas_qtd,
        "price_cents" => habitation.valor_venda_cents.presence || habitation.valor_locacao_cents
      }.compact
    end

    def search_values(attribute)
      key = {
        city: %w[city cidade],
        neighborhood: %w[neighborhood bairro],
        category: %w[category categoria],
        bedrooms: %w[bedrooms dormitorios quartos],
        parking_spaces: %w[parking_spaces vagas]
      }[attribute] || []

      search_events.flat_map do |event|
        params = event.search_params.to_h
        key.filter_map { |name| params[name].presence }
      end
    end

    def habitation_location(habitation, attribute)
      habitation.public_send(attribute).presence || habitation.read_attribute(attribute).presence
    end

    def events
      @events ||= @lead.public_navigation_events.recent.limit(100)
    end

    def property_events
      @property_events ||= events.property_signals
    end

    def search_events
      @search_events ||= events.search_signals
    end

    def explicit_interests
      @explicit_interests ||= @lead.client_property_interests
    end

    def repeated_property_views
      property_events
        .where(name: "property_view")
        .where.not(habitation_id: nil)
        .reorder(nil)
        .group(:habitation_id)
        .count
        .values
        .count { |count| count.to_i > 1 }
    end
  end
end
