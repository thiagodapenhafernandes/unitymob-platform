# frozen_string_literal: true

require "csv"
require "fileutils"
require "set"

module Habitations
  class DevelopmentConstructorBackfillService
    GENERIC_TOKENS = %w[
      construtora incorporadora empreendimentos empreendimento residencial residence edificio edifício
      condominio condomínio tower home club smart village
      de do da dos das e em no na nos nas para por com sem ao aos a o as os
    ].freeze

    Result = Struct.new(
      :missing_total,
      :auto_filled,
      :suggested,
      :unresolved,
      :report_path,
      :rows,
      keyword_init: true
    )

    def initialize(apply: false, min_confidence: 0.78, min_margin: 0.15, tenant: nil)
      @apply = apply
      @min_confidence = min_confidence.to_f
      @min_margin = min_margin.to_f
      @tenant = tenant || Current.tenant
      raise ArgumentError, "Tenant obrigatório para backfill de construtora" if @tenant.blank?
      @constructors = Constructor.order(:id).to_a
      @constructor_tokens = @constructors.each_with_object({}) do |constructor, memo|
        memo[constructor.id] = tokenize(constructor.name)
      end
      @constructor_normalized_names = @constructors.each_with_object({}) do |constructor, memo|
        memo[constructor.id] = normalize(constructor.name)
      end
    end

    def call
      rows = []
      auto_filled = 0

      missing_developments.find_each do |development|
        suggestion = best_suggestion_for(development)
        applied = false

        if @apply && suggestion && suggestion[:auto_apply]
          development.update_columns(
            constructor_id: suggestion[:constructor_id],
            construtora: suggestion[:constructor_name],
            updated_at: Time.current
          )
          applied = true
          auto_filled += 1
        end

        rows << build_row(development, suggestion, applied)
      end

      report_path = write_report(rows)

      Result.new(
        missing_total: rows.size,
        auto_filled: auto_filled,
        suggested: rows.count { |row| row[:suggested_constructor_id].present? },
        unresolved: rows.count { |row| row[:suggested_constructor_id].blank? },
        report_path: report_path,
        rows: rows
      )
    end

    private

    attr_reader :tenant

    def missing_developments
      tenant.habitations.empreendimentos.where(constructor_id: nil)
    end

    def best_suggestion_for(development)
      by_name = exact_name_match_from_other_development(development)
      return by_name if by_name

      fuzzy_name_similarity(development)
    end

    def exact_name_match_from_other_development(development)
      normalized_name = normalize(development.nome_empreendimento)
      return nil if normalized_name.blank?

      candidates = tenant.habitations.empreendimentos
                         .where.not(id: development.id)
                         .where.not(constructor_id: nil)
                         .where("lower(unaccent(nome_empreendimento)) = ?", normalized_name)
                         .distinct
                         .pluck(:constructor_id)
                         .compact
                         .uniq

      return nil unless candidates.one?

      constructor = @constructors.find { |item| item.id == candidates.first }
      return nil if constructor.nil?

      {
        constructor_id: constructor.id,
        constructor_name: constructor.name,
        confidence: 1.0,
        reason: "exact_development_name_match",
        auto_apply: true
      }
    end

    def fuzzy_name_similarity(development)
      dev_tokens = tokenize(development.nome_empreendimento)
      dev_normalized_name = normalize(development.nome_empreendimento)
      return nil if dev_normalized_name.blank?

      ranked = @constructors.filter_map do |constructor|
        ctor_tokens = @constructor_tokens[constructor.id]
        intersection = dev_tokens & ctor_tokens
        token_score =
          if intersection.empty? || ctor_tokens.empty? || dev_tokens.empty?
            0.0
          else
            precision = intersection.size.to_f / ctor_tokens.size
            recall = intersection.size.to_f / dev_tokens.size
            (0.75 * precision) + (0.25 * recall)
          end
        trigram_score = trigram_similarity(dev_normalized_name, @constructor_normalized_names[constructor.id])
        score = [token_score, trigram_score].max
        next if score <= 0.0

        reason =
          if token_score >= trigram_score && intersection.any?
            "token_similarity(#{intersection.join('|')})"
          else
            "trigram_similarity"
          end

        {
          constructor_id: constructor.id,
          constructor_name: constructor.name,
          confidence: score.round(4),
          reason: reason,
          auto_apply: false
        }
      end

      return nil if ranked.empty?

      ranked.sort_by! { |item| -item[:confidence] }
      best = ranked.first
      second = ranked.second

      return nil if best[:confidence] < @min_confidence
      return nil if second && (best[:confidence] - second[:confidence]) < @min_margin

      best
    end

    def build_row(development, suggestion, applied)
      {
        development_id: development.id,
        development_code: development.codigo,
        development_name: development.nome_empreendimento,
        current_constructor_id: development.constructor_id,
        current_constructor_name: development.construtora,
        suggested_constructor_id: suggestion&.dig(:constructor_id),
        suggested_constructor_name: suggestion&.dig(:constructor_name),
        confidence: suggestion&.dig(:confidence),
        reason: suggestion&.dig(:reason),
        applied: applied
      }
    end

    def write_report(rows)
      FileUtils.mkdir_p(Rails.root.join("tmp", "reports"))
      path = Rails.root.join(
        "tmp",
        "reports",
        "development_constructor_backfill_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv"
      )

      CSV.open(path, "w") do |csv|
        csv << rows.first&.keys || %w[development_id development_code development_name]
        rows.each { |row| csv << row.values }
      end

      path.to_s
    end

    def tokenize(value)
      normalize(value)
        .split
        .reject { |token| token.length < 2 || GENERIC_TOKENS.include?(token) }
        .uniq
    end

    def normalize(value)
      I18n.transliterate(value.to_s)
          .downcase
          .gsub(/[^a-z0-9]+/, " ")
          .squeeze(" ")
          .strip
    end

    def trigram_similarity(left, right)
      return 0.0 if left.blank? || right.blank?

      left_set = trigrams(left)
      right_set = trigrams(right)
      return 0.0 if left_set.empty? || right_set.empty?

      intersection = (left_set & right_set).size
      union = (left_set | right_set).size
      return 0.0 if union.zero?

      intersection.to_f / union
    end

    def trigrams(value)
      normalized = "  #{value}  "
      return [normalized].to_set if normalized.length < 3

      set = Set.new
      (0..normalized.length - 3).each do |index|
        set << normalized[index, 3]
      end
      set
    end
  end
end
