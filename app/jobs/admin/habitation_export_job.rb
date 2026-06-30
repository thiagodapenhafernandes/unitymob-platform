require "csv"

module Admin
  # Gera o CSV de imóveis em background, atualizando o progresso, e anexa o arquivo
  # ao HabitationExport. Os ids já foram resolvidos (filtrados/ordenados) no controller.
  class HabitationExportJob < ApplicationJob
    queue_as :default

    BATCH = 500

    def perform(export_id)
      export = HabitationExport.find_by(id: export_id)
      log_export(:warn, "[HabitationExportJob] export_id=#{export_id} status=missing") unless export
      return unless export

      Current.set(tenant: export.tenant) do
        export.update!(status: "processing", progress: 0)

        ids = Array(export.source_ids).map(&:to_i)
        fields = Array(export.fields)
        total = [ids.size, 1].max
        done = 0
        last_logged_progress = -1

        log_export(
          :info,
          "[HabitationExportJob] export_id=#{export.id} user_id=#{export.admin_user_id} status=started records=#{ids.size} fields=#{fields.size}"
        )

        csv = CSV.generate(headers: true, col_sep: export.col_sep) do |out|
          out << Habitations::CsvExporter.header_row(fields)
          ids.each_slice(BATCH) do |slice|
            by_id = export.tenant.habitations.where(id: slice).index_by(&:id)
            slice.each do |id|
              habitation = by_id[id]
              out << Habitations::CsvExporter.row(habitation, fields) if habitation
            end
            done += slice.size
            progress = [(done * 100 / total), 100].min
            export.update_column(:progress, progress)

            if progress == 100 || progress >= last_logged_progress + 10
              log_export(
                :info,
                "[HabitationExportJob] export_id=#{export.id} status=processing progress=#{progress}% done=#{done}/#{ids.size}"
              )
              last_logged_progress = progress
            end
          end
        end

        export.file.attach(
          io: StringIO.new(csv),
          filename: export.filename,
          content_type: "text/csv; charset=utf-8"
        )
        export.update!(status: "completed", progress: 100)
        log_export(
          :info,
          "[HabitationExportJob] export_id=#{export.id} status=completed records=#{ids.size} filename=#{export.filename}"
        )
      end
    rescue StandardError => e
      export&.update(status: "failed", error_message: e.message.to_s[0, 500])
      log_export(
        :error,
        "[HabitationExportJob] export_id=#{export_id} status=failed error=#{e.class}: #{e.message}"
      )
      raise
    end

    private

    def log_export(level, message)
      if defined?(JobRuntimeLogging)
        JobRuntimeLogging.emit(level, message)
      else
        Rails.logger.public_send(level, message)
      end
    end
  end
end
