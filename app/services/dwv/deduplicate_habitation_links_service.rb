module Dwv
  class DeduplicateHabitationLinksService
    def call!
      duplicate_codes = duplicate_codigo_dwv_values
      detached = 0

      duplicate_codes.each do |codigo_dwv|
        result = resolve_for_codigo!(codigo_dwv)
        detached += result[:detached]
      end

      {
        duplicate_groups: duplicate_codes.size,
        detached: detached
      }
    end

    def resolve_for_codigo!(codigo_dwv)
      rows = dwv_scope.where(codigo_dwv: codigo_dwv.to_s).order(*canonical_order).to_a
      return { detached: 0, kept_id: rows.first&.id } if rows.size <= 1

      kept = rows.first
      duplicates = rows.drop(1)
      duplicate_ids = duplicates.map(&:id)
      timestamp = Time.current

      Habitation.where(id: duplicate_ids).update_all(
        codigo_dwv: nil,
        imovel_dwv: "Não",
        last_sync_at: timestamp,
        last_sync_status: "deduplicated",
        last_sync_message: "Vínculo DWV removido por deduplicação automática (codigo_dwv duplicado)."
      )

      {
        detached: duplicate_ids.size,
        kept_id: kept.id
      }
    end

    private

    def dwv_scope
      Habitation.where(imovel_dwv: "Sim").where.not(codigo_dwv: [nil, ""])
    end

    def duplicate_codigo_dwv_values
      dwv_scope.group(:codigo_dwv).having("COUNT(*) > 1").pluck(:codigo_dwv)
    end

    def canonical_order
      [
        Arel.sql("CASE WHEN last_sync_at IS NULL THEN 1 ELSE 0 END"),
        { last_sync_at: :desc },
        { updated_at: :desc },
        { id: :desc }
      ]
    end
  end
end
