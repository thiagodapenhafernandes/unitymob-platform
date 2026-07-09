# frozen_string_literal: true

require "csv"

module DataHygiene
  class WhitespaceSanitizer
    Result = Struct.new(:updates, :columns, :log_path, keyword_init: true)

    EXCLUDED_COLUMN_NAMES = %w[
      encrypted_password
      reset_password_token
      confirmation_token
      unlock_token
    ].freeze
    EXCLUDED_COLUMNS = {
      "attribute_options" => %w[name]
    }.freeze

    def initialize(execute: false, log_path: nil)
      @execute = execute
      @log_path = log_path || Rails.root.join("log", "whitespace_sanitize_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv")
    end

    def call
      Rails.application.eager_load!

      csv = execute ? CSV.open(log_path, "w") : nil
      write_header(csv)
      counters = { updates: 0, columns: 0 }

      target_columns.each do |model, column|
        affected = affected_count(model, column)
        next if affected.zero?

        counters[:columns] += 1
        counters[:updates] += affected
        write_row(csv, model, column, affected)
        update_records(model, column) if execute
      end

      sanitize_attribute_options(csv, counters)

      clear_caches if execute

      csv&.close
      Result.new(updates: counters[:updates], columns: counters[:columns], log_path: execute ? log_path : nil)
    end

    private

    attr_reader :execute, :log_path

    def target_columns
      ApplicationRecord.descendants.reject(&:abstract_class?).sort_by(&:name).flat_map do |model|
        next [] unless model.table_exists?

        model.columns.filter_map do |column|
          next unless %i[string text].include?(column.type)
          next if column.array
          next if column.name.end_with?("_ciphertext")
          next if EXCLUDED_COLUMN_NAMES.include?(column.name)
          next if EXCLUDED_COLUMNS.fetch(model.table_name, []).include?(column.name)

          [model, column]
        end
      end
    end

    def affected_count(model, column)
      quoted = quoted_column(column)
      model.unscoped.where("#{quoted} IS NOT NULL AND #{quoted} <> #{normalized_sql(column)}").count
    end

    def update_records(model, column)
      quoted = quoted_column(column)
      updates = { column.name => Arel.sql(normalized_sql(column)) }
      updates["updated_at"] = Time.current if model.column_names.include?("updated_at")

      model.unscoped.where("#{quoted} IS NOT NULL AND #{quoted} <> #{normalized_sql(column)}").update_all(updates)
    end

    def normalized_sql(column)
      quoted = quoted_column(column)

      if column.type == :string
        "regexp_replace(btrim(#{quoted}), E'\\\\s+', ' ', 'g')"
      else
        "btrim(#{quoted})"
      end
    end

    def quoted_column(column)
      ActiveRecord::Base.connection.quote_column_name(column.name)
    end

    def clear_caches
      Rails.cache.delete_matched("admin/habitations/form_options/*")
      Rails.cache.delete_matched("admin/habitations/filter_data/*")

      Tenant.find_each { |tenant| Habitation.clear_public_filter_cache_for_tenant(tenant.id) } if defined?(Tenant)
    rescue NotImplementedError
      nil
    end

    def sanitize_attribute_options(csv, counters)
      return unless defined?(AttributeOption)

      grouped_attribute_options.each_value do |options|
        canonical = options.map { |option| AttributeOption.sanitize_name(option.name) }.find(&:present?)
        next if canonical.blank?

        keeper = options.find { |option| option.name == canonical } || options.min_by(&:id)
        affected = options.count { |option| option.id != keeper.id || option.name != canonical }
        next if affected.zero?

        counters[:columns] += 1
        counters[:updates] += affected
        write_row(csv, AttributeOption, AttributeOption.columns_hash.fetch("name"), affected)
        apply_attribute_options_group(keeper, options, canonical) if execute
      end
    end

    def grouped_attribute_options
      groups = Hash.new { |hash, key| hash[key] = [] }

      AttributeOption.order(:id).find_each do |option|
        canonical = AttributeOption.sanitize_name(option.name)
        next if canonical.blank?
        next if option.name == canonical && !attribute_option_duplicate_key?(option, canonical)

        groups[[option.tenant_id, option.context, option.category, AttributeOption.normalized_name_key(canonical)]] << option
      end

      groups
    end

    def attribute_option_duplicate_key?(option, canonical)
      canonical_key = AttributeOption.normalized_name_key(canonical)

      AttributeOption
        .where(tenant_id: option.tenant_id, context: option.context, category: option.category)
        .where.not(id: option.id)
        .select(:id, :name)
        .any? { |candidate| AttributeOption.normalized_name_key(candidate.name) == canonical_key }
    end

    def apply_attribute_options_group(keeper, options, canonical)
      AttributeOption.transaction do
        update_attribute_option_usages(keeper, canonical)
        keeper.update_columns(name: canonical, updated_at: Time.current) if keeper.name != canonical

        options.reject { |option| option.id == keeper.id }.each do |duplicate|
          update_attribute_option_usages(duplicate, canonical)
          duplicate.delete
        end
      end
    end

    def update_attribute_option_usages(option, canonical)
      return if option.name == canonical

      AttributeOptions::SyncUsageService.new(
        context: option.context,
        category: option.category,
        old_name: option.name,
        new_name: canonical,
        action: :rename,
        tenant: option.tenant
      ).call
    end

    def write_header(csv)
      return unless csv

      csv << %w[model table column type records_updated]
    end

    def write_row(csv, model, column, affected)
      return unless csv

      csv << [model.name, model.table_name, column.name, column.type, affected]
    end
  end
end
