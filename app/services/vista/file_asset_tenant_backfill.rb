module Vista
  # Backfill de tenant_id em VistaFileAsset legados (criados antes da coluna).
  # Deriva o tenant pelo imóvel vinculado. Idempotente: só toca tenant_id NULL.
  # Conflitos de unicidade (mesma tripla em dois imóveis do mesmo tenant) são
  # contados e reportados, nunca interrompem o lote — exigem decisão manual.
  class FileAssetTenantBackfill
    Result = Struct.new(:dry_run, :scanned, :updated, :pending, :skipped_orphan, :conflicts, keyword_init: true)

    def initialize(dry_run: true, limit: nil, batch_size: 1000)
      @dry_run = dry_run.to_s != "false" && dry_run != false
      @limit = limit.to_i.positive? ? limit.to_i : nil
      @batch_size = batch_size.to_i.positive? ? batch_size.to_i : 1000
    end

    def call
      scanned = 0
      updated = 0
      skipped_orphan = 0
      conflicts = 0
      scope = VistaFileAsset.where(tenant_id: nil).order(:id)
      scope = scope.limit(@limit) if @limit
      scope.includes(:habitation).find_each(batch_size: @batch_size) do |asset|
        scanned += 1
        tenant_id = asset.habitation&.tenant_id
        if tenant_id.nil?
          skipped_orphan += 1
          next
        end
        next if @dry_run

        begin
          asset.update_column(:tenant_id, tenant_id)
          updated += 1
        rescue ActiveRecord::RecordNotUnique
          conflicts += 1
        end
      end
      Result.new(dry_run: @dry_run, scanned:, updated:, pending: @dry_run ? scanned - skipped_orphan : 0,
        skipped_orphan:, conflicts:)
    end
  end
end
