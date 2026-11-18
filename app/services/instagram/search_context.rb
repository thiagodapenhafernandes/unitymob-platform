module Instagram
  # Memória de critérios declarados pelo cliente; legendas não qualificam intenção.
  class SearchContext
    KEY = "instagram_search".freeze
    FOLLOW_UP = /\A(?:(?:voc[eê] )?(?:tem|possui|h[aá]) |(?:quero|pode|poderia) (?:ver|mostrar|mandar) )?(?:outr[oa]s?|mais) (?:op[cç][oõ]es|im[oó]veis|apartamentos?|casas?)[?!. ]*\z/i
    COUNT_QUESTION = /quant[oa]s?.{0,30}(?:quartos|dormit[oó]rios)/i
    PRICE_QUESTION = /\b(?:faixa|valor|or[cç]amento|pagar|pre[cç]o)\b/i
    PARAM_KEYS = Ai::PropertySearch::PublicParams::COUNT_PARAMS.invert.freeze

    attr_reader :lead, :state

    def initialize(lead)
      @lead = lead
      @state = lead.other_information.to_h[KEY].to_h.deep_dup
    end

    def self.new_search?(text)
      text.match?(CatalogReply::NEW_SEARCH) && !text.match?(FOLLOW_UP)
    end

    def capture!(through: nil)
      return self unless lead.persisted?
      scope = lead.instagram_messages
      scope = scope.where("id <= ?", through) if through
      rows = scope.order(id: :desc).limit(60).to_a.sort_by { |message| [message.occurred_at, message.id] }
      cursor = state["through"].to_i
      question = nil
      rows.each do |message|
        if message.outbound?
          question = message.body.to_s if message.body.to_s.include?("?")
          next
        end
        next if message.id <= cursor || message.body.blank?
        text = message.body.to_s.squish
        @state = {} if self.class.new_search?(text)
        before = state.except("through", "criteria_message_id").deep_dup
        extract(text, question.to_s)
        state["criteria_message_id"] = message.id if before != state.except("through", "criteria_message_id")
        state["through"] = [state["through"].to_i, message.id].max
      end
      persist!
      self
    end

    def filters
      state.fetch("filters", {}).merge(state.fetch("constraints", {}))
    end

    def params
      Ai::PropertySearch::PublicParams.new(filters).call
    end

    def business_type
      state["business_type"]
    end

    def sufficient?
      %w[venda locacao].include?(business_type) && filters["property_type"].present? &&
        (filters["city"].present? || filters["neighborhood"].present?) &&
        (filters["price_max"].to_f.positive? || filters["bedrooms_min"].to_i.positive?)
    end

    def remember!(public_params)
      values = public_params.to_h.stringify_keys
      inferred = PARAM_KEYS.each_with_object({}) { |(param, key), hash| hash[key] = values[param].to_f if values[param].present? }
      inferred["transaction_type"] = {"aluguel" => "rent", "locacao" => "rent", "venda" => "sale"}[values["transaction_type"]]
      inferred["property_type"] = Array(values["category"]).first if values["category"].present?
      inferred["neighborhood"] = values["neighborhood"] if values["neighborhood"].present?
      if (location = Array(values["city"]).first).present?
        neighborhood, city = location.split(" - ", 2)
        inferred[city ? "neighborhood" : "city"] = neighborhood
        inferred["city"] = city if city
      end
      inferred["development_name"] = Array(values["development"]).first if values["development"].present?
      state["filters"] = filters.merge(inferred.compact).merge(state.fetch("constraints", {}))
      persist!
      self
    end

    def apply(scope)
      if state["rental_period"] == "annual"
        scope = scope.where.not(status: "Diária").where("intake_modalidade IS NULL OR intake_modalidade <> ?", "locacao_diaria")
      elsif state["rental_period"] == "daily"
        scope = scope.for_daily_rental
      end
      if state["includes_fees"] && filters["transaction_type"] == "rent" && filters["price_max"].to_f.positive?
        scope = scope.where.not(valor_condominio_cents: nil).where.not(valor_iptu_cents: nil)
          .where.not(valor_condominio_cents: Habitation::STRATEGIC_TAX_PLACEHOLDER_CENTS)
          .where.not(valor_iptu_cents: Habitation::STRATEGIC_TAX_PLACEHOLDER_CENTS)
        scope = scope.where(<<~SQL.squish, (filters["price_max"].to_f * 100).round)
          COALESCE(valor_locacao_cents, 0) +
          CASE WHEN valor_condominio_cents > 1 THEN valor_condominio_cents ELSE 0 END +
          CASE WHEN valor_iptu_cents > 1 THEN valor_iptu_cents ELSE 0 END <= ?
        SQL
      end
      scope
    end

    def summary
      parts = Ai::PropertySearch::PublicParams.summary(filters)
      parts << "Locação anual" if state["rental_period"] == "annual"
      parts << "Orçamento incluindo encargos cadastrados" if state["includes_fees"]
      parts.join(" · ")
    end

    private

    def extract(text, question)
      return if text.match?(Qualification::NEGATIVE) || text.match?(Qualification::OWNER)
      constraints = state.fetch("constraints", {})
      mode = CaptureAnswer.new(text).business_type
      if mode.in?(%w[venda locacao diaria])
        state["business_type"] = mode
        constraints["transaction_type"] = mode == "venda" ? "sale" : "rent"
      end
      constraints["transaction_type"] = "rent" if text.match?(/\A(?:aluguel|loca[cç][aã]o|alugar)\?\z/i)
      if text.match?(/\banual\b/i)
        state["rental_period"] = "annual"
      elsif text.match?(/\b(?:di[aá]ria|temporada)\b/i)
        state["rental_period"] = "daily"
      end
      {"Apartamento" => /\b(?:apartamentos?|apto|ap[êe])\b/i, "Casa" => /\bcasas?\b/i, "Terreno" => /\b(?:terrenos?|lotes?)\b/i}.each do |category, pattern|
        constraints["property_type"] = category if text.match?(pattern)
      end
      count = text.match(/\b(\d{1,2})\s*(?:quartos|dormit[oó]rios)\b/i)&.[](1)
      count ||= text[/\A\d{1,2}\z/] if question.match?(COUNT_QUESTION)
      constraints["bedrooms_min"] = count.to_i if count && count.to_i.between?(1, 20)
      amount = text.match(/(?:at[eé]|or[cç]amento(?: de)?|R\$)\s*(?:uns?\s+)?([\d.,]+)\s*(milh(?:[aã]o|[oõ]es)|mil)?/i)
      amount ||= text.match(/\A([\d.,]+)\s*(milh(?:[aã]o|[oõ]es)|mil)?\z/i) if question.match?(PRICE_QUESTION)
      if amount
        raw = amount[1].include?(',') || amount[1].match?(/\A\d{1,3}(?:\.\d{3})+\z/) ? amount[1].delete('.').tr(',', '.') : amount[1]
        value = raw.to_f
        value *= 1_000_000 if amount[2].to_s.match?(/milh/i)
        value *= 1000 if amount[2].to_s.downcase == "mil" || (amount[2].blank? && value < 100 && constraints["transaction_type"] == "rent" && state["rental_period"] != "daily")
        constraints["price_max"] = value if value.positive? && value <= 1_000_000_000
      end
      state["includes_fees"] = true if text.match?(/\b(?:com|c)\s+(?:as\s+)?taxas\b|inclu[ií]ndo (?:as )?(?:taxas|condom[ií]nio)/i)
      state["constraints"] = constraints
    end

    def persist!
      return unless lead.persisted?
      return if lead.other_information.to_h[KEY] == state
      lead.update_columns(other_information: lead.other_information.to_h.merge(KEY => state))
    end
  end
end
