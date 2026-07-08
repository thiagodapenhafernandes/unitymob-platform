# frozen_string_literal: true

require "csv"
require "json"

module DataHygiene
  class LocationValueSanitizer
    TARGETS = [
      [Habitation, %w[cidade bairro bairro_comercial]],
      [Address, %w[cidade bairro bairro_comercial]]
    ].freeze

    SMALL_WORDS = %w[da de do das dos e].freeze
    ACCENT_FIXES = {
      "balneario" => "Balneário",
      "camboriu" => "Camboriú",
      "picarras" => "Piçarras",
      "sao" => "São",
      "municipios" => "Municípios",
      "pereque" => "Perequê",
      "itajai" => "Itajaí"
    }.freeze

    Result = Struct.new(:updates, :groups, :log_path, keyword_init: true)

    def initialize(execute: false, log_path: nil)
      @execute = execute
      @log_path = log_path || Rails.root.join("log", "location_sanitize_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv")
    end

    def call
      csv = execute ? CSV.open(log_path, "w") : nil
      write_header(csv)
      counters = { updates: 0, groups: 0 }

      TARGETS.each do |model, fields|
        fields.each do |field|
          groups_for(model, field).each do |group|
            values = JSON.parse(group.fetch("values_json")).map(&:to_s).reject { |value| value.squish.blank? }
            canonical = canonical_value(values)
            next if canonical.blank?

            variants = values.uniq.reject { |value| value == canonical }
            next if variants.blank?

            counters[:groups] += 1
            variants.each do |variant|
              affected = count_records(model, field, variant)
              counters[:updates] += affected
              write_row(csv, model, field, group.fetch("key"), variant, canonical, affected)
              update_records(model, field, variant, canonical) if execute
            end
          end
        end
      end

      Rails.cache.delete_matched("admin/habitations/form_options/*") if execute
      Rails.cache.delete_matched("admin/habitations/filter_data/*") if execute

      csv&.close
      Result.new(updates: counters[:updates], groups: counters[:groups], log_path: execute ? log_path : nil)
    end

    private

    attr_reader :execute, :log_path

    def groups_for(model, field)
      table = model.table_name
      sql = <<~SQL.squish
        SELECT #{normalized_sql(field)} AS key,
               json_agg(DISTINCT #{field}) AS values_json
        FROM #{table}
        WHERE NULLIF(TRIM(#{field}), '') IS NOT NULL
        GROUP BY #{normalized_sql(field)}
        HAVING COUNT(DISTINCT #{field}) > 1
      SQL

      ActiveRecord::Base.connection.select_all(sql).map(&:to_h)
    end

    def normalized_sql(field)
      "lower(regexp_replace(unaccent(trim(#{field})), '\\s+', ' ', 'g'))"
    end

    def canonical_value(values)
      variants = Array(values).map(&:to_s).map(&:squish).reject(&:blank?)
      return if variants.blank?

      counts = variants.tally
      preferred = counts.max_by { |value, count| [count, canonical_score(value)] }&.first
      pretty_value(preferred)
    end

    def canonical_score(value)
      [
        value.scan(/[[:upper:]]/).size,
        value.scan(/[áéíóúâêôãõçÁÉÍÓÚÂÊÔÃÕÇ]/).size,
        -value.scan(/[[:upper:]]{2,}/).size,
        value.length
      ]
    end

    def pretty_value(value)
      value.to_s.squish.split.map.with_index do |word, index|
        normalized = I18n.transliterate(word).downcase
        next SMALL_WORDS.include?(normalized) ? normalized : word if word.match?(/\A[[:upper:]][[:lower:]áéíóúâêôãõç]+\z/)
        next SMALL_WORDS.include?(normalized) ? normalized : ACCENT_FIXES.fetch(normalized, normalized.mb_chars.titleize.to_s) if word == word.downcase || word == word.upcase

        index.zero? ? word.mb_chars.titleize.to_s : word
      end.join(" ")
    end

    def count_records(model, field, value)
      model.where(field => value).count
    end

    def update_records(model, field, old_value, new_value)
      model.where(field => old_value).update_all(field => new_value, updated_at: Time.current)
    end

    def write_header(csv)
      return unless csv

      csv << %w[model field key old_value canonical_value records_updated]
    end

    def write_row(csv, model, field, key, old_value, canonical, affected)
      return unless csv

      csv << [model.name, field, key, old_value, canonical, affected]
    end
  end
end
