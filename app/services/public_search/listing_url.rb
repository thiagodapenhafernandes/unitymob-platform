module PublicSearch
  # Core novo de URLs amigáveis da busca pública (/imoveis/...).
  #
  # Fonte única server-side: monta (.build) e interpreta (#params_for) a
  # gramática nova. O legado (FriendlyUrl + JS) segue intacto até a migração
  # das campanhas; este serviço não é usado por ele.
  #
  # Gramática (ordem fixa, segmentos vazios omitidos, `+` para OU):
  #   /imoveis/{transação}/{categorias}/{locais}/{quartos}/{suítes}/
  #     {vagas}/{banheiros}/{área}/{preço}/{características}/{busca}
  # Apenas `page` e `sort` continuam como query string.
  class ListingUrl
    PATH_TRANSACTIONS = {
      "venda" => "venda",
      "aluguel" => "aluguel"
    }.freeze

    BLANK_SEGMENTS = %w[todos todas all qualquer].freeze

    EXACT_COUNT_PATTERN = /\A(\d+)-(quarto|quartos|suite|suites|vaga|vagas|banheiro|banheiros)\z/.freeze
    MIN_COUNT_PATTERN = /\A(\d+)-mais-(quartos|suites|vagas|banheiros)\z/.freeze
    COUNT_DIMENSIONS = {
      "quarto" => :bedrooms, "quartos" => :bedrooms,
      "suite" => :suites, "suites" => :suites,
      "vaga" => :parking, "vagas" => :parking,
      "banheiro" => :bathrooms, "banheiros" => :bathrooms
    }.freeze
    MIN_COUNT_DIMENSIONS = {
      "quartos" => :min_bedrooms,
      "suites" => :min_suites,
      "vagas" => :min_parking,
      "banheiros" => :min_bathrooms
    }.freeze
    EXACT_TO_MIN_DIMENSION = {
      bedrooms: :min_bedrooms,
      suites: :min_suites,
      parking: :min_parking,
      bathrooms: :min_bathrooms
    }.freeze

    AREA_PATTERN = /\A(?:(ate|a-partir-de|acima-de)-)?(\d+)(?:-(\d+))?m2\z/.freeze

    AMOUNT_PATTERN = /(?:\d+-(?:mil|milhao|milhoes)|\d+)/.freeze
    PRICE_PATTERN = /\A(?:(ate|a-partir-de|acima-de)-)?(#{AMOUNT_PATTERN})(?:-(#{AMOUNT_PATTERN}))?\z/.freeze

    SEARCH_PREFIX = "busca-".freeze

    # Flags avulsas do backend unificadas no bloco de características.
    EXTRA_CHARACTERISTICS = {
      "aceita-permuta" => :accepts_exchange,
      "aceita-financiamento" => :accepts_financing
    }.freeze

    def initialize(tenant:)
      @tenant = tenant
    end

    # Guarda da rota nova (puro, sem banco): só captura URLs na gramática
    # nova. URLs legadas (categorias/locais simples, até 3 segmentos
    # opcionais) caem na rota `friendly_habitations` como hoje.
    def self.matches?(path)
      parts = path.to_s.split("/").reject(&:blank?)
      return false unless parts[0] == "imoveis" && PATH_TRANSACTIONS.key?(parts[1])

      rest = parts[2..] || []
      return false if rest.empty?
      return true if rest.size > 3

      rest.any? { structural_segment?(_1) }
    end

    def self.structural_segment?(segment)
      text = segment.to_s
      return true if text.start_with?(SEARCH_PREFIX)
      return true if price_segment?(text) || area_part?(slug(text))

      text.split("+").any? do |part|
        slug_part = slug(part)
        count_part?(slug_part) || characteristic_part?(slug_part)
      end
    end

    # Monta o path a partir dos filtros internos (sem tenant: só slugifica
    # rótulos canônicos, sem lookup).
    def self.build(filters = {})
      filters = filters.to_h.with_indifferent_access
      segments = [normalize_transaction(filters[:transaction_type] || filters[:finalidade])]

      append_values(segments, filters[:category] || filters[:tipo])
      append_values(segments, filters[:city] || filters[:cidade])
      append_counts(segments, filters)
      append_area(segments, filters)
      append_price(segments, filters)
      append_characteristics(segments, filters)
      append_search(segments, filters)

      "/imoveis/#{segments.join("/")}"
    end

    # Interpreta `imoveis/:listing_transaction/*listing_filters`.
    # Retorna nil quando algum slug é desconhecido (controller responde 404).
    def params_for(transaction, filters_string)
      result = {}
      normalized = self.class.normalize_transaction(transaction)
      return nil if normalized.nil?

      result[:transaction_type] = normalized
      segments = filters_string.to_s.split("/").reject(&:blank?)

      segments.each do |segment|
        parsed = parse_segment(segment)
        return nil if parsed.nil?

        merge_parsed(result, parsed)
      end

      result
    end

    def self.blank_segment?(value)
      BLANK_SEGMENTS.include?(slug(value))
    end

    def self.slug(value)
      FriendlyUrl.slug_for(value)
    end

    def self.normalize_transaction(value)
      PATH_TRANSACTIONS[slug(value)] || PATH_TRANSACTIONS[slug(value).delete_suffix("s")]
    end

    private

    attr_reader :tenant

    def parse_segment(segment)
      raw = segment.to_s
      if raw.start_with?(SEARCH_PREFIX)
        query = self.class.slug(raw.delete_prefix(SEARCH_PREFIX)).tr("-", " ").squish
        return query.present? ? { search: query } : nil
      end

      text = self.class.slug(raw)
      if (price = parse_price_segment(text))
        return price
      end
      if (area = parse_area_part(text))
        return area
      end

      parsed = {}
      segment.to_s.split("+").each do |raw_part|
        part = self.class.slug(raw_part)
        next if BLANK_SEGMENTS.include?(part) || part.blank?

        return nil unless classify_part(parsed, part)
      end
      parsed
    end

    def classify_part(parsed, part)
      if (count = parse_count_part(part))
        key, value = count
        if key.to_s.start_with?("min_")
          parsed[key] = value
        else
          parsed[key] = (Array(parsed[key]) + [value]).uniq
        end
        return true
      end

      canonical = FriendlyUrl::CHARACTERISTICS[part]
      if canonical
        parsed[:characteristics] = (Array(parsed[:characteristics]) + [canonical]).uniq
        return true
      end

      flag = EXTRA_CHARACTERISTICS[part]
      if flag
        parsed[flag] = "1"
        return true
      end

      if (label = category_lookup[part])
        parsed[:category] = (Array(parsed[:category]) + [label]).uniq
        return true
      end

      if (label = location_lookup[part])
        parsed[:city] = (Array(parsed[:city]) + [label]).uniq
        return true
      end

      # Leniência espelhada no legado: categoria desconhecida vira rótulo
      # (página 200 vazia em vez de 404 — seguro para campanhas).
      parsed[:category] = (Array(parsed[:category]) + [part.tr("-", " ").titleize]).uniq
      true
    end

    # Vocabulário igual às pills (1–3 exato, 4+ mínimo): exato >= 4 vira
    # mínimo 4; "N-mais" preserva o mínimo verbatim (fiel ao backend).
    def parse_count_part(part)
      if (match = part.match(EXACT_COUNT_PATTERN))
        number = match[1].to_i
        dimension = COUNT_DIMENSIONS[match[2]]
        if number >= 4
          [EXACT_TO_MIN_DIMENSION.fetch(dimension), 4]
        else
          [dimension, number]
        end
      elsif (match = part.match(MIN_COUNT_PATTERN))
        [MIN_COUNT_DIMENSIONS[match[2]], match[1].to_i]
      end
    end

    def parse_area_part(part)
      match = part.match(AREA_PATTERN)
      return nil unless match

      prefix, first, second = match[1], match[2].to_i, match[3]&.to_i
      case prefix
      when "ate" then { max_area: first }
      when "a-partir-de", "acima-de" then { min_area: first }
      else
        second ? { min_area: first, max_area: second } : { min_area: first }
      end
    end

    def parse_price_segment(text)
      match = text.match(PRICE_PATTERN)
      return nil unless match
      return nil if match[2].nil? && match[3].nil?

      prefix, first, second = match[1], parse_amount(match[2]), parse_amount(match[3])
      return nil if first.nil? && second.nil?

      case prefix
      when "ate" then { max_price: first || second }
      when "a-partir-de", "acima-de" then { min_price: first || second }
      else
        second ? { min_price: first, max_price: second } : { min_price: first }
      end
    end

    def parse_amount(text)
      return nil if text.nil?

      if (match = text.match(/\A(\d+)-(mil|milhao|milhoes)\z/))
        multiplier = match[2] == "mil" ? 1_000 : 1_000_000
        match[1].to_i * multiplier
      elsif text.match?(/\A\d+\z/)
        text.to_i
      end
    end

    def merge_parsed(result, parsed)
      parsed.each do |key, value|
        if value.is_a?(Array)
          result[key] = (Array(result[key]) + value).uniq
        else
          result[key] = value
        end
      end
    end

    def category_lookup
      @category_lookup ||= tenant.habitations.public_property_types.index_by { |value| self.class.slug(value) }
    end

    def location_lookup
      @location_lookup ||= tenant.habitations.public_location_options
        .map { |option| option[:value].to_s }
        .index_by { |value| self.class.slug(value) }
    end

    class << self
      private

      def price_segment?(text)
        !text.match(PRICE_PATTERN).nil? && text.exclude?("+")
      end

      def area_part?(slug_part)
        !slug_part.match(AREA_PATTERN).nil?
      end

      def count_part?(slug_part)
        slug_part.match?(EXACT_COUNT_PATTERN) || slug_part.match?(MIN_COUNT_PATTERN)
      end

      def characteristic_part?(slug_part)
        FriendlyUrl::CHARACTERISTICS.key?(slug_part) || EXTRA_CHARACTERISTICS.key?(slug_part)
      end

      def append_values(segments, values)
        slugs = Array(values).flat_map { |value| value.to_s.split("+") }
          .map { |value| slug(value) }.reject(&:blank?)
          .reject { |part| BLANK_SEGMENTS.include?(part) }.uniq
        segments << slugs.join("+") if slugs.any?
      end

      # Espelha as pills (single-select): mínimo presente vence os exatos
      # (backend aplicaria AND entre eles); exato >= 4 colapsa para 4+.
      def append_counts(segments, filters)
        {
          bedrooms: ["quarto", "quartos", :min_bedrooms],
          suites: ["suite", "suites", :min_suites],
          parking: ["vaga", "vagas", :min_parking],
          bathrooms: ["banheiro", "banheiros", :min_bathrooms]
        }.each do |exact_key, (singular, plural, min_key)|
          minimum = filters[min_key].to_i
          if minimum.positive?
            segments << "#{minimum}-mais-#{plural}"
            next
          end

          numbers = Array(filters[exact_key]).map { |value| value.to_i }.select(&:positive?).uniq.sort
          if numbers.any? { |number| number >= 4 }
            segments << "4-mais-#{plural}"
          elsif numbers.any?
            segments << numbers.map { |number| number == 1 ? "1-#{singular}" : "#{number}-#{plural}" }.join("+")
          end
        end
      end

      def append_area(segments, filters)
        min_area = filters[:min_area].to_i
        max_area = filters[:max_area].to_i
        if min_area.positive? && max_area.positive?
          segments << "#{min_area}-#{max_area}m2"
        elsif max_area.positive?
          segments << "ate-#{max_area}m2"
        elsif min_area.positive?
          segments << "a-partir-de-#{min_area}m2"
        end
      end

      def append_price(segments, filters)
        min_price, max_price = resolve_price(filters)
        if min_price.positive? && max_price.positive?
          segments << "#{format_amount(min_price)}-#{format_amount(max_price)}"
        elsif max_price.positive?
          segments << "ate-#{format_amount(max_price)}"
        elsif min_price.positive?
          segments << "a-partir-de-#{format_amount(min_price)}"
        end
      end

      # price_range ("3200000-5800000", do form da home) vira min/max quando
      # eles não vieram — mesmo formato aceito em search_params.
      def resolve_price(filters)
        min_price = filters[:min_price].to_i
        max_price = filters[:max_price].to_i
        if min_price.zero? && max_price.zero?
          range = filters[:price_range].to_s.strip
          if range.match?(/\A\d{1,12}(?:-\d{1,12})?\z/)
            first, second = range.split("-", 2).map(&:to_i)
            min_price = first
            max_price = second || 0
          end
        end
        [min_price, max_price]
      end

      def format_amount(value)
        if (value % 1_000_000).zero?
          number = value / 1_000_000
          number == 1 ? "1-milhao" : "#{number}-milhoes"
        elsif value < 1_000_000 && (value % 1_000).zero?
          "#{(value / 1_000)}-mil"
        else
          # Valor quebrado acima de 1M (ex: 3.2M): número cru, exato e
          # sem ambiguidade com faixa ("3-milhoes-200-mil" leria como range).
          value.to_s
        end
      end

      def append_characteristics(segments, filters)
        reverse = FriendlyUrl::CHARACTERISTICS.invert
        slugs = Array(filters[:characteristics]).filter_map do |value|
          reverse[value.to_s] || slug(value.to_s).presence
        end
        slugs << "mobiliado" if truthy_filter?(filters[:furnished]) && slugs.exclude?("mobiliado")
        slugs << "aceita-permuta" if truthy_filter?(filters[:accepts_exchange])
        slugs << "aceita-financiamento" if truthy_filter?(filters[:accepts_financing])
        slugs = slugs.map { |value| slug(value) }.reject(&:blank?).uniq
        segments << slugs.join("+") if slugs.any?
      end

      def append_search(segments, filters)
        query = (filters[:search].presence || filters[:q].presence).to_s.squish
        return if query.blank?

        segments << "#{SEARCH_PREFIX}#{slug(query)}"
      end

      def truthy_filter?(value)
        value == true || value.to_s == "1"
      end
    end
  end
end
