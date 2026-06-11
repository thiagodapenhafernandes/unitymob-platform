class Admin::DwvIntegrationsController < Admin::BaseController
  before_action :require_admin!
  before_action :load_dwv_state, only: [:show, :status]

  DEFAULT_BASE_URL = "https://agencies.dwvapp.com.br".freeze
  DEFAULT_SYNC_LIMIT = 50
  DEFAULT_SYNC_MAX_PAGES = 100
  DEFAULT_POLL_PROCESSING_MS = 2000
  DEFAULT_POLL_IDLE_MS = 6000
  DEFAULT_POLL_SLOW_MS = 15000
  DEFAULT_REQUEST_PAUSE_SECONDS = 0.70

  def show
  end

  def status
    render :status, layout: false
  end

  def update
    enabled = ActiveModel::Type::Boolean.new.cast(dwv_params[:enabled])
    new_token = dwv_params[:api_token].to_s.strip

    Setting.set("dwv_enabled", enabled.to_s, "Habilita integração com DWV")
    if new_token.present?
      Setting.set("dwv_api_token", new_token, "Token da API DWV")
    end
    Setting.set("dwv_base_url", normalized_base_url(dwv_params[:base_url]), "URL base da API DWV")
    Setting.set("dwv_sync_limit", dwv_params[:sync_limit].to_i.clamp(1, 50).to_s, "Limite por página da sincronização DWV")
    Setting.set("dwv_sync_max_pages", dwv_params[:sync_max_pages].to_i.clamp(1, 100).to_s, "Máximo de páginas da sincronização DWV")
    Setting.set("dwv_request_pause_seconds", dwv_params[:request_pause_seconds].to_f.clamp(0.2, 2.0).round(2).to_s, "Pausa entre requisições DWV em segundos")
    Setting.set("dwv_poll_processing_interval_ms", dwv_params[:poll_processing_interval_ms].to_i.clamp(1000, 30000).to_s, "Polling DWV (processing) em ms")
    Setting.set("dwv_poll_idle_interval_ms", dwv_params[:poll_idle_interval_ms].to_i.clamp(2000, 60000).to_s, "Polling DWV (idle/skipped) em ms")
    Setting.set("dwv_poll_slow_interval_ms", dwv_params[:poll_slow_interval_ms].to_i.clamp(5000, 120000).to_s, "Polling DWV (completed/failed) em ms")

    redirect_to admin_dwv_integrations_path, notice: "Configuração DWV salva com sucesso."
  rescue => e
    redirect_to admin_dwv_integrations_path, alert: "Erro ao salvar configuração DWV: #{e.message}"
  end

  def test_connection
    ensure_enabled_and_token!

    client = dwv_client
    response = client.list_properties(limit: 1, page: 1)
    total = Dwv::PropertyImportService.extract_collection(response).size

    redirect_to admin_dwv_integrations_path, notice: "Conexão DWV validada com sucesso. Retorno: #{total} item(ns) no lote de teste."
  rescue => e
    redirect_to admin_dwv_integrations_path, alert: "Falha ao validar conexão DWV: #{e.message}"
  end

  def sync_property
    ensure_enabled_and_token!

    property_id = params[:property_id].to_s.strip
    return redirect_to(admin_dwv_integrations_path, alert: "Informe o ID do imóvel na DWV.") if property_id.blank?

    payload = dwv_client.property_details(property_id)
    result = Dwv::PropertyImportService.new(payload).perform

    stamp_sync!("Imóvel DWV ##{property_id} sincronizado. Código local: #{result[:habitation].codigo}")
    redirect_to admin_dwv_integrations_path, notice: "Imóvel sincronizado com sucesso."
  rescue => e
    stamp_sync!("Erro ao sincronizar imóvel DWV ##{params[:property_id]}: #{e.message}")
    redirect_to admin_dwv_integrations_path, alert: "Falha na sincronização do imóvel: #{e.message}"
  end

  def sync_now
    ensure_enabled_and_token!
    mark_processing!("Sincronização DWV em background iniciada manualmente.")

    DwvSyncJob.perform_later(
      mode: "full",
      triggered_by_id: current_admin_user.id
    )

    redirect_to admin_dwv_integrations_path, notice: "Sincronização DWV iniciada em segundo plano."
  rescue => e
    stamp_sync!("Erro ao iniciar sincronização DWV: #{e.message}")
    redirect_to admin_dwv_integrations_path, alert: "Falha ao iniciar sincronização DWV: #{e.message}"
  end

  def sync_recent
    ensure_enabled_and_token!

    limit = params[:limit].to_i
    limit = Setting.get("dwv_sync_limit", DEFAULT_SYNC_LIMIT.to_s).to_i if limit <= 0
    limit = [limit, 50].min
    mark_processing!("Sincronização de lote DWV (1 página) iniciada em background.")

    DwvSyncJob.perform_later(
      mode: "batch",
      limit: limit,
      max_pages: 1,
      triggered_by_id: current_admin_user.id
    )

    redirect_to admin_dwv_integrations_path, notice: "Sincronização em lote iniciada em segundo plano."
  rescue => e
    stamp_sync!("Erro na sincronização em lote: #{e.message}")
    redirect_to admin_dwv_integrations_path, alert: "Falha na sincronização em lote: #{e.message}"
  end

  def deactivate_removed
    ensure_enabled_and_token!
    mark_processing!("Desativação de removidos DWV iniciada em background.")

    DwvSyncJob.perform_later(
      mode: "deactivate_removed",
      triggered_by_id: current_admin_user.id
    )

    redirect_to admin_dwv_integrations_path, notice: "Desativação de removidos iniciada em segundo plano."
  rescue => e
    stamp_sync!("Erro ao desativar removidos DWV: #{e.message}")
    redirect_to admin_dwv_integrations_path, alert: "Falha ao desativar removidos: #{e.message}"
  end

  private

  def load_dwv_state
    status_service = Dwv::SyncStatusService.new

    @dwv_enabled = Setting.get("dwv_enabled", "false") == "true"
    @dwv_api_token = Setting.get("dwv_api_token", "")
    @dwv_connected = @dwv_enabled && @dwv_api_token.present?
    @dwv_base_url = Setting.get("dwv_base_url", DEFAULT_BASE_URL)
    @dwv_sync_limit = Setting.get("dwv_sync_limit", DEFAULT_SYNC_LIMIT.to_s).to_i.clamp(1, 50)
    @dwv_sync_max_pages = Setting.get("dwv_sync_max_pages", DEFAULT_SYNC_MAX_PAGES.to_s).to_i.clamp(1, 100)
    @dwv_sync_status = Setting.get("dwv_sync_status")
    @dwv_sync_progress = Setting.get("dwv_sync_progress", "0").to_i.clamp(0, 100)
    @dwv_sync_history = status_service.history(limit: 5)
    @dwv_request_pause_seconds = Setting.get("dwv_request_pause_seconds", DEFAULT_REQUEST_PAUSE_SECONDS.to_s).to_f.clamp(0.2, 2.0)
    @dwv_poll_processing_interval_ms = Setting.get("dwv_poll_processing_interval_ms", DEFAULT_POLL_PROCESSING_MS.to_s).to_i.clamp(1000, 30000)
    @dwv_poll_idle_interval_ms = Setting.get("dwv_poll_idle_interval_ms", DEFAULT_POLL_IDLE_MS.to_s).to_i.clamp(2000, 60000)
    @dwv_poll_slow_interval_ms = Setting.get("dwv_poll_slow_interval_ms", DEFAULT_POLL_SLOW_MS.to_s).to_i.clamp(5000, 120000)
    @dwv_last_sync_at = Setting.get("dwv_last_sync_at")
    @dwv_last_sync_message = Setting.get("dwv_last_sync_message")
    @dwv_last_error_summary = parse_error_summary(Setting.get("dwv_last_error_summary", "{}"))
    @dwv_last_sync_time = Time.zone.parse(@dwv_last_sync_at.to_s)
    @dwv_worker_health = fetch_worker_health
  rescue ArgumentError, TypeError
    @dwv_last_sync_time = nil
    @dwv_last_error_summary = {}
    @dwv_worker_health = fallback_worker_health
  end

  def dwv_params
    params.require(:dwv).permit(
      :enabled,
      :api_token,
      :base_url,
      :sync_limit,
      :sync_max_pages,
      :request_pause_seconds,
      :poll_processing_interval_ms,
      :poll_idle_interval_ms,
      :poll_slow_interval_ms
    )
  end

  def normalized_base_url(value)
    base = value.to_s.strip
    return DEFAULT_BASE_URL if base.blank?

    base.chomp("/")
  end

  def dwv_client
    Dwv::Client.new(
      token: Setting.get("dwv_api_token"),
      base_url: Setting.get("dwv_base_url", DEFAULT_BASE_URL)
    )
  end

  def ensure_enabled_and_token!
    enabled = Setting.get("dwv_enabled", "false") == "true"
    token = Setting.get("dwv_api_token").to_s

    raise "Ative a integração DWV antes de sincronizar." unless enabled
    raise "Token DWV não configurado." if token.blank?
  end

  def stamp_sync!(message)
    Setting.set("dwv_last_sync_at", Time.current.iso8601, "Última execução DWV")
    Dwv::SyncStatusService.new.update_progress!(progress: Setting.get("dwv_sync_progress", "0").to_i, message: message.to_s)
  end

  def mark_processing!(message)
    Setting.set("dwv_sync_status", "processing", "Status da sincronização DWV")
    Setting.set("dwv_sync_progress", "5", "Progresso percentual da sincronização DWV")
    Setting.set("dwv_last_sync_message", message.to_s, "Resumo da última execução DWV")
  end

  def parse_error_summary(raw)
    parsed = JSON.parse(raw.to_s)
    return {} unless parsed.is_a?(Hash)

    parsed.transform_keys(&:to_s).sort_by { |_, count| -count.to_i }.to_h
  rescue JSON::ParserError
    {}
  end

  def fetch_worker_health
    return fallback_worker_health("Solid Queue não está disponível nesta instalação.") unless defined?(SolidQueue::Process)

    # Solid Queue updates heartbeat roughly every ~60s in this setup.
    # Using 45s creates false "offline" flapping on the dashboard.
    heartbeat_threshold = 2.minutes.ago
    worker_scope = SolidQueue::Process.where(kind: "Worker")
    scheduler_scope = SolidQueue::Process.where(kind: "Scheduler")
    online_workers = worker_scope.where("last_heartbeat_at >= ?", heartbeat_threshold)
    online = online_workers.exists?
    queue_ready = defined?(SolidQueue::ReadyExecution) ? SolidQueue::ReadyExecution.count : 0
    last_worker_heartbeat = worker_scope.maximum(:last_heartbeat_at)
    scheduler_online = scheduler_scope.where("last_heartbeat_at >= ?", heartbeat_threshold).exists?

    {
      online: online,
      scheduler_online: scheduler_online,
      queue_ready: queue_ready,
      worker_count: online_workers.count,
      last_heartbeat_at: last_worker_heartbeat,
      message: worker_health_message(online:, queue_ready:)
    }
  rescue => e
    fallback_worker_health("Falha ao ler saúde da fila: #{e.message}")
  end

  def worker_health_message(online:, queue_ready:)
    return "Worker processando normalmente." if online
    return "Worker offline com #{queue_ready} job(s) pendente(s) na fila." if queue_ready.positive?

    "Worker offline no momento."
  end

  def fallback_worker_health(message = "Saúde da fila indisponível.")
    {
      online: false,
      scheduler_online: false,
      queue_ready: 0,
      worker_count: 0,
      last_heartbeat_at: nil,
      message: message
    }
  end
end
