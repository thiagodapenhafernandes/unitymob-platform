# Watchdog do SolidQueue (config/recurring.yml, a cada 5 min): loga alertas
# grepáveis com o prefixo [QUEUE_ALERT] e notifica os Admins do Sistema via
# Web Push quando a fila degrada. Roda na fila checkin (worker dedicado) para
# não depender da fila default monitorada.
#
# Ponto cego conhecido: o scheduler roda dentro do próprio supervisor do
# SolidQueue — se o serviço inteiro morrer, este job para junto. O cenário
# "processo morto" precisa de monitoramento externo (systemd/uptime check).
class QueueHealthCheckJob < ApplicationJob
  queue_as :checkin

  FAILED_EXECUTIONS_THRESHOLD = ENV.fetch("QUEUE_ALERT_FAILED_THRESHOLD", "200").to_i
  READY_MAX_AGE_MINUTES = ENV.fetch("QUEUE_ALERT_READY_MAX_AGE_MINUTES", "10").to_i
  HEARTBEAT_STALE_MINUTES = ENV.fetch("QUEUE_ALERT_HEARTBEAT_STALE_MINUTES", "5").to_i
  # Push no máximo a cada 30 min; o log sai a cada tick enquanto degradado.
  PUSH_THROTTLE = 30.minutes
  PUSH_THROTTLE_CACHE_KEY = "queue_health_check:last_push_alert".freeze

  def perform
    alerts = [failed_executions_alert, stale_ready_alert, dead_worker_alert].compact
    return if alerts.empty?

    alerts.each { |alert| Rails.logger.error("[QUEUE_ALERT] #{alert}") }
    notify_system_admins(alerts)
  end

  private

  def failed_executions_alert
    count = SolidQueue::FailedExecution.count
    return nil if count <= FAILED_EXECUTIONS_THRESHOLD

    "failed_executions=#{count} acima do limite (#{FAILED_EXECUTIONS_THRESHOLD}) — revisar em /jobs (Mission Control)."
  end

  def stale_ready_alert
    oldest = SolidQueue::ReadyExecution.minimum(:created_at)
    return nil if oldest.blank? || oldest > READY_MAX_AGE_MINUTES.minutes.ago

    age_minutes = ((Time.current - oldest) / 60).round
    "fila acumulando: job pronto há #{age_minutes} min sem worker (ready=#{SolidQueue::ReadyExecution.count})."
  end

  def dead_worker_alert
    cutoff = HEARTBEAT_STALE_MINUTES.minutes.ago
    return nil if SolidQueue::Process.where(kind: "Worker").where("last_heartbeat_at > ?", cutoff).exists?

    "nenhum worker SolidQueue com heartbeat nos últimos #{HEARTBEAT_STALE_MINUTES} min — verificar o serviço solid_queue."
  end

  def notify_system_admins(alerts)
    return unless push_throttle_allows?

    body = alerts.join(" | ").truncate(240)
    AdminUser.where(super_admin: true).pluck(:id).each do |admin_user_id|
      Notifications::PushDispatcher.deliver(
        admin_user_id: admin_user_id,
        title: "Alerta de filas (SolidQueue)",
        body: body,
        url: "/jobs",
        tag: "queue_alert"
      )
    rescue StandardError => e
      Rails.logger.warn("[QUEUE_ALERT] push falhou para admin_user_id=#{admin_user_id}: #{e.message}")
    end
  end

  # write com unless_exist só retorna true quando a chave não existia:
  # dedup natural da notificação dentro da janela de throttle.
  def push_throttle_allows?
    Rails.cache.write(PUSH_THROTTLE_CACHE_KEY, Time.current.to_i, unless_exist: true, expires_in: PUSH_THROTTLE)
  end
end
