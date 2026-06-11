require "set"

class LoftSyncJob < ApplicationJob
  queue_as :default

  def perform(mode: "full", batch_size: nil, triggered_by_id: nil)
    lock_service = Loft::SyncLockService.new(
      lock_key: "loft_sync_lock",
      lease_seconds: ENV.fetch("LOFT_SYNC_LOCK_LEASE_SECONDS", "5400")
    )
    lock_owner = lock_service.acquire
    status_service = Loft::SyncStatusService.new

    unless lock_owner.present?
      status_service.mark_skipped!(mode: mode, message: "Loft sync ignorado: já existe uma sincronização em andamento.")
      return
    end

    status_service.mark_processing!(mode: mode, message: "Sincronização Loft iniciada.", progress: 5)

    host = Setting.get("loft_host").to_s.presence || ENV.fetch("VISTA_HOST", "")
    token = Setting.get("loft_token").to_s.presence || ENV.fetch("VISTA_KEY", "")
    raise "Host Loft não configurado." if host.blank?
    raise "Token Loft não configurado." if token.blank?

    normalized_mode = mode.to_s == "batch" ? "batch" : "full"
    size = batch_size.to_i.positive? ? batch_size.to_i : Setting.get("loft_sync_batch_size", "100").to_i
    listing = Loft::PropertyCodesService.new(host: host, token: token).call(mode: normalized_mode, batch_size: size)
    codes = listing[:codes]
    categorias = listing[:categorias] || {}
    parent_codes = listing[:parent_codes] || Set.new

    if codes.blank?
      status_service.mark_skipped!(mode: normalized_mode, message: "Nenhum imóvel encontrado para sincronização.")
      return
    end

    # Empreendimentos/pais primeiro (validação de codigo_empreendimento_must_exist em unidades filhas).
    # É pai se Categoria="Empreendimento" OU se algum outro imóvel referencia este código.
    empreendimentos, unidades = codes.partition do |c|
      categorias[c].to_s.casecmp("Empreendimento").zero? || parent_codes.include?(c)
    end
    codes = empreendimentos + unidades

    dwv_codes = Habitation.where(codigo: codes, imovel_dwv: "Sim").pluck(:codigo).map(&:to_s).to_set
    codes_to_sync = codes.reject { |code| dwv_codes.include?(code.to_s) }
    existing_codes = Habitation.where(codigo: codes_to_sync).pluck(:codigo).map(&:to_s).to_set

    result = Vista::PropertyReconciliationService.new(
      codigos: codes_to_sync,
      dry_run: false,
      host: host,
      key: token,
      replace_photos: true,
      replace_documents: true,
      download_files: false,
      workers: ENV.fetch("LOFT_SYNC_WORKERS", "4").to_i,
      progress_callback: lambda do |progress|
        lock_service.refresh(lock_owner)
        status_service.update_progress!(
          progress: progress[:percent].to_i.clamp(5, 99),
          message: "Reconciliação Vista (#{progress[:current]}/#{progress[:total]}) | atualizados=#{progress[:updated]} | ignorados=#{progress[:skipped]} | erros=#{progress[:failed]}"
        )
      end
    ).call

    updated_codes = result.rows.select { |row| row[:status] == "updated" }.map { |row| row[:codigo].to_s }
    created = updated_codes.count { |code| !existing_codes.include?(code) }
    updated = updated_codes.size - created
    errors_count = result.failed
    skipped_dwv = dwv_codes.size
    processed = result.scanned + skipped_dwv
    hidden_missing = normalized_mode == "full" ? hide_missing_from_vista_api!(codes) : 0

    message = [
      "Reconciliação Vista (#{normalized_mode}) concluída",
      "processados=#{processed}",
      "criados=#{created}",
      "atualizados=#{updated}",
      "pulados_dwv=#{skipped_dwv}",
      "ocultados_fora_api=#{hidden_missing}",
      "erros=#{errors_count}",
      "fotos_reaproveitadas=#{result.photos_reused}",
      "fotos_pendentes_download=#{result.photos_pending_download}",
      "documentos_reaproveitados=#{result.documents_reused}",
      "documentos_pendentes_download=#{result.documents_pending_download}",
      "total_remoto=#{listing[:remote_total]}",
      ("triggered_by=#{triggered_by_id}" if triggered_by_id.present?)
    ].compact.join(" | ")

    status_service.mark_completed!(
      mode: normalized_mode,
      message: message,
      stats: {
        processed: processed,
        created: created,
        updated: updated,
        skipped_dwv: skipped_dwv,
        hidden_missing: hidden_missing,
        errors_count: errors_count,
        remote_total: listing[:remote_total],
        photos_reused: result.photos_reused,
        photos_pending_download: result.photos_pending_download,
        documents_reused: result.documents_reused,
        documents_pending_download: result.documents_pending_download,
        report_path: result.report_path
      }
    )
  rescue => e
    status_service&.mark_failed!(mode: mode, message: "Loft sync falhou: #{e.message}")
    raise e
  ensure
    lock_service&.release(lock_owner)
  end

  private

  def hide_missing_from_vista_api!(api_codes)
    now = Time.current
    Habitation
      .where(Habitation::VISTA_REFERENCE_CODIGO_SQL)
      .where.not(codigo: api_codes.map(&:to_s))
      .where("exibir_no_site_flag = TRUE OR exibir_no_site_salute_flag = TRUE OR last_sync_status <> ?", "missing_from_vista_api")
      .update_all(
        exibir_no_site_flag: false,
        exibir_no_site_salute_flag: false,
        last_sync_status: "missing_from_vista_api",
        last_sync_message: "Ocultado porque não retornou na API Vista em #{now.strftime("%d/%m/%Y %H:%M")}",
        last_sync_at: now,
        updated_at: now
      )
  end
end
