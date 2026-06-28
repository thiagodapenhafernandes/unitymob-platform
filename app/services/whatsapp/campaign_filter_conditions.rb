module Whatsapp
  class CampaignFilterConditions
    FIELD_DEFINITIONS = {
      "status" => { label: "Status do funil", operators: %w[in equals] },
      "origin" => { label: "Canal/origem", operators: %w[in contains equals] },
      "admin_user_id" => { label: "Responsável", operators: %w[equals in] },
      "tags" => { label: "Tags", operators: %w[with_any without_any] },
      "created_at" => { label: "Data de criação", operators: %w[between since until] },
      "name" => { label: "Nome do lead", operators: %w[contains equals] },
      "email" => { label: "E-mail", operators: %w[contains present blank] },
      "phone" => { label: "Telefone", operators: %w[contains present blank] }
    }.freeze

    Result = Struct.new(:scope, :summary, :conditions, keyword_init: true)

    def self.call(scope: Lead.all, definition: {}, legacy_filters: {})
      new(scope:, definition:, legacy_filters:).call
    end

    def initialize(scope:, definition:, legacy_filters:)
      @scope = scope
      @definition = definition.to_h.with_indifferent_access
      @legacy_filters = legacy_filters.to_h.with_indifferent_access
    end

    def call
      normalized = normalized_conditions
      scoped = normalized.reduce(scope) { |relation, condition| apply_condition(relation, condition) }
      Result.new(scope: scoped.distinct, summary: summary_for(normalized), conditions: normalized)
    end

    private

    attr_reader :scope, :definition, :legacy_filters

    def normalized_conditions
      raw_conditions = Array(definition[:conditions]).filter_map { |item| normalize_condition(item) }
      return raw_conditions if raw_conditions.any?

      legacy_conditions.filter_map { |item| normalize_condition(item) }
    end

    def legacy_conditions
      [
        legacy_filters[:status].present? ? { "field" => "status", "operator" => "equals", "value" => legacy_filters[:status] } : nil,
        legacy_filters[:origin].present? ? { "field" => "origin", "operator" => "equals", "value" => legacy_filters[:origin] } : nil,
        legacy_filters[:admin_user_id].present? ? { "field" => "admin_user_id", "operator" => "equals", "value" => legacy_filters[:admin_user_id] } : nil
      ].compact
    end

    def normalize_condition(raw)
      data = raw.to_h.with_indifferent_access
      field = data[:field].to_s
      return unless FIELD_DEFINITIONS.key?(field)

      operator = data[:operator].presence || default_operator_for(field)
      operator = default_operator_for(field) unless FIELD_DEFINITIONS[field][:operators].include?(operator)
      values = Array(data[:values].presence || data[:value]).map { |value| value.to_s.strip }.reject(&:blank?)
      from = data[:from].to_s.strip.presence
      to = data[:to].to_s.strip.presence
      return if values.blank? && from.blank? && to.blank? && !%w[present blank].include?(operator)

      { "field" => field, "operator" => operator, "values" => values, "from" => from, "to" => to }.compact
    end

    def default_operator_for(field)
      FIELD_DEFINITIONS.fetch(field)[:operators].first
    end

    def apply_condition(relation, condition)
      field = condition.fetch("field")
      operator = condition.fetch("operator")
      values = Array(condition["values"])

      case field
      when "status"
        statuses = values.map { |value| Lead.status_value(value) }
        operator == "equals" ? relation.where(status: statuses.first) : relation.where(status: statuses)
      when "origin"
        operator == "in" ? relation.where(origin: values) : apply_text_condition(relation, :origin, operator, values)
      when "admin_user_id"
        ids = values.filter_map { |value| Integer(value, exception: false) }
        operator == "equals" ? relation.where(admin_user_id: ids.first) : relation.where(admin_user_id: ids)
      when "tags"
        operator == "without_any" ? relation.without_any_tags(values) : relation.with_any_tags(values)
      when "created_at"
        apply_date_condition(relation, :created_at, operator, condition)
      when "name"
        apply_text_condition(relation, :name, operator, values)
      when "email"
        apply_text_condition(relation, :email, operator, values)
      when "phone"
        apply_text_condition(relation, :phone, operator, values)
      else
        relation
      end
    end

    def apply_text_condition(relation, column, operator, values)
      case operator
      when "equals"
        relation.where(column => values.first)
      when "present"
        relation.where.not(column => [nil, ""])
      when "blank"
        relation.where(column => [nil, ""])
      else
        values.reduce(relation) { |current, value| current.where("#{column} ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(value)}%") }
      end
    end

    def apply_date_condition(relation, column, operator, condition)
      from = parse_date(condition["from"])
      to = parse_date(condition["to"])

      case operator
      when "since"
        from ? relation.where("#{column} >= ?", from.beginning_of_day) : relation
      when "until"
        to ? relation.where("#{column} <= ?", to.end_of_day) : relation
      else
        relation = relation.where("#{column} >= ?", from.beginning_of_day) if from
        relation = relation.where("#{column} <= ?", to.end_of_day) if to
        relation
      end
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end

    def summary_for(conditions)
      return "Todos os leads com telefone" if conditions.blank?

      conditions.map do |condition|
        label = FIELD_DEFINITIONS.dig(condition["field"], :label) || condition["field"]
        values = Array(condition["values"]).join(", ")
        range = [condition["from"], condition["to"]].compact.join(" até ")
        operator_label = operator_label_for(condition["operator"])
        "#{label}: #{operator_label} #{values.presence || range.presence || ''}".squish
      end.join(" · ")
    end

    def operator_label_for(operator)
      {
        "contains" => "contém",
        "equals" => "igual a",
        "in" => "um destes",
        "with_any" => "com",
        "without_any" => "sem",
        "present" => "preenchido",
        "blank" => "vazio",
        "between" => "entre",
        "since" => "desde",
        "until" => "até"
      }.fetch(operator.to_s, operator.to_s)
    end
  end
end
