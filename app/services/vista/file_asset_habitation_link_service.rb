module Vista
  class FileAssetHabitationLinkService
    Result = Struct.new(:batch_id, :dry_run, :linked, keyword_init: true)

    def initialize(batch: VistaImportBatch.latest_first.first, dry_run: true)
      @batch = batch
      @dry_run = ActiveModel::Type::Boolean.new.cast(dry_run)
    end

    def call
      raise ArgumentError, "Nenhum batch Vista raw encontrado" unless @batch

      linked = matching_scope.count
      link_assets! unless @dry_run

      Result.new(batch_id: @batch.id, dry_run: @dry_run, linked: linked)
    end

    private

    def matching_scope
      VistaFileAsset
        .joins("INNER JOIN habitations ON habitations.codigo = vista_file_assets.codigo_imovel AND habitations.vista_import_batch_id = vista_file_assets.vista_import_batch_id")
        .where(vista_import_batch_id: @batch.id, habitation_id: nil, kind: %w[property_photo property_document])
        .where.not(codigo_imovel: [nil, ""])
    end

    def link_assets!
      quoted_now = ActiveRecord::Base.connection.quote(Time.current)

      ActiveRecord::Base.connection.exec_update(<<~SQL.squish, "Vista file asset habitation link")
        UPDATE vista_file_assets
           SET habitation_id = habitations.id,
               updated_at = #{quoted_now}
          FROM habitations
         WHERE habitations.codigo = vista_file_assets.codigo_imovel
           AND habitations.vista_import_batch_id = vista_file_assets.vista_import_batch_id
           AND vista_file_assets.vista_import_batch_id = #{@batch.id.to_i}
           AND vista_file_assets.habitation_id IS NULL
           AND vista_file_assets.kind IN ('property_photo', 'property_document')
           AND vista_file_assets.codigo_imovel IS NOT NULL
           AND vista_file_assets.codigo_imovel <> ''
      SQL
    end
  end
end
