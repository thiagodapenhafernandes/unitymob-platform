# frozen_string_literal: true

require "csv"
require "set"

module Proprietors
  class DuplicateMerger
    REFERENCING_TABLES = DuplicateAnalyzer::REFERENCING_TABLES
    COALESCE_SKIP_COLUMNS = %w[
      id tenant_id created_at updated_at name vista_code cpf_cnpj_digits spouse_cpf_cnpj_digits
    ].freeze

    Result = Struct.new(
      :groups,
      :deleted,
      :repointed,
      :skipped,
      :log_path,
      keyword_init: true
    )

    def initialize(candidates:, risks:, execute: false, log_path: nil)
      @candidates = candidates
      @risks = Array(risks).map(&:to_s)
      @execute = execute
      @log_path = log_path || Rails.root.join("log", "proprietor_merge_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv")
    end

    def call
      counters = { groups: 0, deleted: 0, repointed: 0, skipped: 0 }
      seen_duplicate_ids = Set.new
      csv = execute ? CSV.open(log_path, "w") : nil
      write_header(csv)

      filtered_candidates.each do |candidate|
        ActiveRecord::Base.transaction do
          canonical = Proprietor.lock.find_by(id: candidate.canonical_id, tenant_id: candidate.tenant_id)
          unless canonical
            counters[:skipped] += 1
            next
          end

          duplicate_ids = candidate.duplicate_ids - seen_duplicate_ids.to_a
          duplicates = Proprietor.lock.where(id: duplicate_ids, tenant_id: candidate.tenant_id).order(:id).to_a
          if duplicates.blank?
            counters[:skipped] += 1
            next
          end

          counters[:groups] += 1

          duplicates.each do |duplicate|
            moved = merge_duplicate(canonical, duplicate, candidate, csv)
            counters[:repointed] += moved
            counters[:deleted] += 1
            seen_duplicate_ids << duplicate.id
          end

          canonical.save! if execute && canonical.changed?
        end
      rescue StandardError => e
        counters[:skipped] += 1
        Rails.logger.warn("[proprietor_merge] candidate=#{candidate.match_type}:#{candidate.match_key} error=#{e.class}: #{e.message}")
      end

      csv&.close

      Result.new(
        groups: counters[:groups],
        deleted: counters[:deleted],
        repointed: counters[:repointed],
        skipped: counters[:skipped],
        log_path: execute ? log_path : nil
      )
    end

    private

    attr_reader :candidates, :risks, :execute, :log_path

    def filtered_candidates
      candidates.select { |candidate| risks.include?(candidate.risk) }
    end

    def merge_duplicate(canonical, duplicate, candidate, csv)
      moved = repoint_references(canonical, duplicate)
      coalesce_missing_attributes(canonical, duplicate)
      write_row(csv, candidate, canonical, duplicate, moved)
      duplicate.destroy! if execute
      moved
    end

    def repoint_references(canonical, duplicate)
      REFERENCING_TABLES.sum do |table|
        next count_references(table, duplicate.id) unless execute

        ActiveRecord::Base.connection.update(
          ActiveRecord::Base.sanitize_sql_array(
            ["UPDATE #{table} SET proprietor_id = ? WHERE proprietor_id = ?", canonical.id, duplicate.id]
          )
        )
      end
    end

    def count_references(table, proprietor_id)
      ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array(["SELECT COUNT(*) FROM #{table} WHERE proprietor_id = ?", proprietor_id])
      ).to_i
    end

    def coalesce_missing_attributes(canonical, duplicate)
      return unless execute

      (Proprietor.column_names - COALESCE_SKIP_COLUMNS).each do |column|
        canonical[column] = duplicate[column] if canonical[column].blank? && duplicate[column].present?
      end
    end

    def write_header(csv)
      return unless csv

      csv << %w[
        tenant_id risk match_type match_key canonical_id duplicate_id duplicate_name
        duplicate_vista_code references_repointed
      ]
    end

    def write_row(csv, candidate, canonical, duplicate, moved)
      return unless csv

      csv << [
        candidate.tenant_id,
        candidate.risk,
        candidate.match_type,
        candidate.match_key,
        canonical.id,
        duplicate.id,
        duplicate.name,
        duplicate.vista_code,
        moved
      ]
    end
  end
end
