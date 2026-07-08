module InterestIntelligence
  class Matcher
    Result = Struct.new(:habitation, :score, :reasons, keyword_init: true)

    def self.call(lead, limit: nil)
      new(lead, limit: limit).call
    end

    def initialize(lead, limit: nil)
      @lead = lead
      @settings = InterestIntelligence::Settings.current
      @profile = InterestIntelligence::ProfileBuilder.call(lead).with_indifferent_access
      @limit = limit || @settings["max_suggestions"].to_i
    end

    def call
      return [] unless @settings.enabled?
      return [] if profile_incomplete?
      return [] if @lead&.tenant_id.blank?

      candidate_scope.limit(250).filter_map do |habitation|
        score, reasons = score_for(habitation)
        next if score < @settings["minimum_match_score"].to_i

        Result.new(habitation: habitation, score: score, reasons: reasons)
      end.sort_by { |result| -result.score }.first(@limit)
    end

    def profile
      @profile
    end

    def profile_incomplete?
      criteria = @profile[:criteria] || {}
      criteria[:cities].blank? && criteria[:neighborhoods].blank? && criteria[:categories].blank? && criteria[:max_price_cents].blank?
    end

    private

    def candidate_scope
      # Escopo obrigatório por tenant: sem ele a sugestão vazaria imóveis de
      # outras imobiliárias (Habitation não tem default_scope de tenant).
      scope = Habitation.for_tenant(@lead.tenant_id).active.with_price
      criteria = @profile[:criteria] || {}

      if criteria[:cities].present?
        scope = scope.where(cidade: criteria[:cities])
      end

      scope.order(updated_at: :desc)
    end

    def score_for(habitation)
      score = 0
      reasons = []
      criteria = @profile[:criteria] || {}

      if matches_list?(habitation_location(habitation, :cidade), criteria[:cities])
        score += weight(:city)
        reasons << "cidade compatível"
      end

      if matches_list?(habitation_location(habitation, :bairro), criteria[:neighborhoods])
        score += weight(:neighborhood)
        reasons << "bairro compatível"
      end

      if matches_list?(habitation.categoria, criteria[:categories])
        score += weight(:category)
        reasons << "tipo compatível"
      end

      if criteria[:bedrooms].present? && habitation.dormitorios_qtd.to_i == criteria[:bedrooms].to_i
        score += weight(:bedrooms)
        reasons << "dormitórios compatíveis"
      end

      if criteria[:parking_spaces].present? && habitation.vagas_qtd.to_i == criteria[:parking_spaces].to_i
        score += weight(:parking)
        reasons << "vagas compatíveis"
      end

      if price_compatible?(habitation)
        score += weight(:price)
        reasons << "faixa de preço compatível"
      end

      [normalized_score(score), reasons]
    end

    def matches_list?(value, list)
      return false if value.blank? || list.blank?

      list.map { |item| item.to_s.parameterize }.include?(value.to_s.parameterize)
    end

    def price_compatible?(habitation)
      criteria = @profile[:criteria] || {}
      min = criteria[:min_price_cents].to_i
      max = criteria[:max_price_cents].to_i
      return false if min.zero? && max.zero?

      price = habitation.valor_venda_cents.presence || habitation.valor_locacao_cents
      return false if price.to_i <= 0

      tolerance = @settings["price_tolerance_percent"].to_i / 100.0
      lower = min.positive? ? (min * (1 - tolerance)).to_i : 0
      upper = max.positive? ? (max * (1 + tolerance)).to_i : Float::INFINITY

      price >= lower && price <= upper
    end

    def habitation_location(habitation, attribute)
      habitation.public_send(attribute).presence || habitation.read_attribute(attribute).presence
    end

    def weight(name)
      @settings["#{name}_weight"].to_i
    end

    def maximum_score
      %i[city neighborhood category bedrooms parking price].sum { |name| weight(name) }.presence || 100
    end

    def normalized_score(score)
      ((score.to_f / maximum_score) * 100).round.clamp(0, 100)
    end
  end
end
