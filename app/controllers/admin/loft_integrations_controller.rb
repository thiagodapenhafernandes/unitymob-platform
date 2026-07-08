require "fugit"

class Admin::LoftIntegrationsController < Admin::BaseController
  before_action :require_admin!
  before_action :load_state

  def show
  end

  def update
    enabled = ActiveModel::Type::Boolean.new.cast(loft_params[:enabled])
    host = loft_params[:host].to_s.strip
    token = loft_params[:token].to_s.strip

    preserve_manual_fields = ActiveModel::Type::Boolean.new.cast(loft_params[:preserve_manual_fields])

    Setting.set("loft_enabled", enabled.to_s, "Habilita integração Loft Soft")
    Setting.set("loft_host", normalize_host(host), "Host da API Loft Soft") if host.present?
    Setting.set("loft_token", token, "Token da API Loft Soft") if token.present?
    Setting.set("loft_preserve_manual_fields", preserve_manual_fields.to_s, "Preserva campos manuais para imóveis já sincronizados do Loft")
    Setting.set("loft_sync_batch_size", loft_params[:sync_batch_size].to_i.clamp(1, 1000).to_s, "Batch size da sync Loft")
    Setting.set("loft_images_sync_limit", loft_params[:images_sync_limit].to_i.clamp(1, 500).to_s, "Limite por sync de imagens Loft")
    Setting.set("loft_poll_processing_interval_ms", loft_params[:poll_processing_interval_ms].to_i.clamp(1000, 30000).to_s, "Polling processing Loft")
    Setting.set("loft_poll_idle_interval_ms", loft_params[:poll_idle_interval_ms].to_i.clamp(2000, 60000).to_s, "Polling idle Loft")
    Setting.set("loft_poll_slow_interval_ms", loft_params[:poll_slow_interval_ms].to_i.clamp(5000, 120000).to_s, "Polling slow Loft")

    redirect_to admin_loft_integrations_path, notice: "Configuração Loft Soft salva com sucesso."
  rescue => e
    redirect_to admin_loft_integrations_path, alert: "Erro ao salvar configuração Loft Soft: #{e.message}"
  end

  def test_connection
    host = current_host
    token = current_token

    raise "Host não configurado." if host.blank?
    raise "Token não configurado." if token.blank?

    response = RestClient.get(
      "#{host}/imoveis/listar",
      params: {
        key: token,
        pesquisa: {
          fields: ["Codigo"],
          paginacao: { pagina: 1, quantidade: 1 }
        }.to_json,
        showtotal: 1,
        showSuspended: 1
      },
      accept: :json
    )

    parsed = JSON.parse(response.body) rescue nil
    unless parsed.is_a?(Hash)
      return redirect_to admin_loft_integrations_path, alert: "Resposta inesperada ao testar Loft Soft."
    end

    api_status = parsed["status"].to_i
    if api_status >= 400
      api_message = parsed["message"].presence || parsed["msg"].presence || "erro na API"
      return redirect_to admin_loft_integrations_path, alert: "Falha ao testar conexão Loft Soft: #{api_message}"
    end

    redirect_to admin_loft_integrations_path, notice: "Conexão com Loft Soft validada (host e token aceitos)."
  rescue RestClient::ExceptionWithResponse => e
    body = e.response&.body.to_s
    parsed_error = JSON.parse(body) rescue {}
    api_message = parsed_error["message"].presence || parsed_error["msg"].presence
    error_text = api_message.presence || "#{e.response&.code || e.http_code} #{e.message}"
    redirect_to admin_loft_integrations_path, alert: "Falha ao testar conexão Loft Soft: #{error_text}"
  rescue => e
    redirect_to admin_loft_integrations_path, alert: "Falha ao testar conexão Loft Soft: #{e.message}"
  end

  def sync_property
    ensure_enabled_and_credentials!
    code = params[:property_code].to_s.strip
    return redirect_to(admin_loft_integrations_path, alert: "Informe o código do imóvel.") if code.blank?

    result = Vista::PropertyReconciliationService.new(
      codigos: [code],
      dry_run: false,
      host: current_host,
      key: current_token,
      replace_photos: true,
      replace_documents: true,
      download_files: false,
      workers: 1
    ).call
    row = result.rows.first || {}

    if row[:status] == "updated"
      Loft::SyncStatusService.new.mark_completed!(
        mode: "property",
        message: "Imóvel #{code} reconciliado pela API Vista.",
        stats: {
          processed: 1,
          updated: 1,
          errors_count: 0,
          photos_api: row[:photos_api],
          photos_reused: row[:photos_reused],
          photos_pending_download: row[:photos_pending_download],
          documents_reused: row[:documents_reused],
          documents_pending_download: row[:documents_pending_download]
        }
      )
      redirect_to admin_loft_integrations_path, notice: "Imóvel #{code} reconciliado com sucesso pela API Vista."
    else
      reason = row[:reason].presence || row[:errors].presence || "sem retorno válido da API"
      Loft::SyncStatusService.new.mark_failed!(mode: "property", message: "Falha no imóvel #{code}: #{reason}")
      redirect_to admin_loft_integrations_path, alert: "Falha ao reconciliar imóvel #{code}: #{reason}"
    end
  rescue => e
    Loft::SyncStatusService.new.mark_failed!(mode: "property", message: "Falha no imóvel #{code}: #{e.message}")
    redirect_to admin_loft_integrations_path, alert: "Erro ao sincronizar imóvel: #{e.message}"
  end

  def sync_now
    ensure_enabled_and_credentials!
    LoftSyncJob.perform_later(mode: "full", batch_size: Setting.get("loft_sync_batch_size", "100").to_i, tenant_id: current_tenant.id, triggered_by_id: current_admin_user.id)
    redirect_to admin_loft_integrations_path, notice: "Reconciliação completa pela API Vista iniciada em segundo plano."
  rescue => e
    redirect_to admin_loft_integrations_path, alert: "Falha ao iniciar reconciliação Vista: #{e.message}"
  end

  def sync_batch
    ensure_enabled_and_credentials!
    LoftSyncJob.perform_later(mode: "batch", batch_size: Setting.get("loft_sync_batch_size", "100").to_i, tenant_id: current_tenant.id, triggered_by_id: current_admin_user.id)
    redirect_to admin_loft_integrations_path, notice: "Reconciliação em lote pela API Vista iniciada."
  rescue => e
    redirect_to admin_loft_integrations_path, alert: "Falha ao iniciar lote Vista: #{e.message}"
  end

  def sync_images_now
    ensure_enabled_and_credentials!
    LoftImagesSyncJob.perform_later(limit: Setting.get("loft_images_sync_limit", "100").to_i, tenant_id: current_tenant.id, triggered_by_id: current_admin_user.id)
    redirect_to admin_loft_integrations_path, notice: "Sincronização de imagens para Spaces iniciada."
  rescue => e
    redirect_to admin_loft_integrations_path, alert: "Falha ao iniciar sync de imagens: #{e.message}"
  end

  def status
    load_state
    render :status, layout: false
  end

  private

  def load_state
    @loft_enabled = Setting.get("loft_enabled", "false") == "true"
    @loft_host = current_host
    @loft_token = current_token
    @loft_sync_status = Setting.get("loft_sync_status", "idle")
    @loft_sync_progress = Setting.get("loft_sync_progress", "0").to_i.clamp(0, 100)
    @loft_last_sync_message = Setting.get("loft_last_sync_message")
    @loft_last_sync_at = Setting.get("loft_last_sync_at")
    @loft_last_sync_time = Time.zone.parse(@loft_last_sync_at.to_s) rescue nil
    @loft_sync_history = Loft::SyncStatusService.new.history(limit: 5)
    @loft_preserve_manual_fields = Setting.get("loft_preserve_manual_fields", "true") == "true"
    @loft_sync_batch_size = Setting.get("loft_sync_batch_size", "100").to_i.clamp(1, 1000)
    @loft_images_sync_limit = Setting.get("loft_images_sync_limit", "100").to_i.clamp(1, 500)
    @loft_poll_processing_interval_ms = Setting.get("loft_poll_processing_interval_ms", "2000").to_i.clamp(1000, 30000)
    @loft_poll_idle_interval_ms = Setting.get("loft_poll_idle_interval_ms", "6000").to_i.clamp(2000, 60000)
    @loft_poll_slow_interval_ms = Setting.get("loft_poll_slow_interval_ms", "15000").to_i.clamp(5000, 120000)
  end

  def current_host
    Setting.get("loft_host").to_s.presence || ENV.fetch("VISTA_HOST", "").to_s
  end

  def current_token
    Setting.get("loft_token").to_s.presence || ENV.fetch("VISTA_KEY", "").to_s
  end

  def loft_params
    params.require(:loft).permit(
      :enabled, :host, :token,
      :preserve_manual_fields,
      :sync_batch_size, :images_sync_limit,
      :poll_processing_interval_ms, :poll_idle_interval_ms, :poll_slow_interval_ms
    )
  end

  def normalize_host(value)
    value.to_s.strip.chomp("/")
  end



  def ensure_enabled_and_credentials!
    raise "Integração Loft Soft desativada." unless @loft_enabled
    raise "Host não configurado." if @loft_host.blank?
    raise "Token não configurado." if @loft_token.blank?
  end
end
