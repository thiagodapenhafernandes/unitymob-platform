# frozen_string_literal: true

# Health check profundo (GET /healthz): prova banco (SELECT 1), cache Rails e
# worker SolidQueue vivo (heartbeat < 5 min — mesmo threshold do
# process_alive_threshold do SolidQueue). O /up default do Rails continua
# existindo como check de boot.
#
# Herda de ActionController::Base de propósito: sem hooks de Devise/tenant
# do ApplicationController, sem sessão — barato e amigável a uptime monitor.
# O corpo expõe só ok/fail por componente; o detalhe do erro vai pro log.
class HealthController < ActionController::Base
  def check
    results = {
      db: check_db,
      cache: check_cache,
      queue: check_queue
    }

    status = results.values.all?("ok") ? :ok : :service_unavailable
    render json: results, status: status
  end

  private

  def check_db
    ActiveRecord::Base.connection_pool.with_connection { |conn| conn.select_value("SELECT 1") }
    "ok"
  rescue StandardError => e
    log_failure(:db, e)
  end

  def check_cache
    return "ok" if Rails.cache.is_a?(ActiveSupport::Cache::NullStore)

    key = "healthz:cache:#{request.request_id}"
    Rails.cache.write(key, "ok", expires_in: 30.seconds)
    result = Rails.cache.read(key) == "ok" ? "ok" : log_failure(:cache, StandardError.new("cache não confirmou leitura"))
    Rails.cache.delete(key)
    result
  rescue StandardError => e
    Rails.cache.delete(key) if key
    log_failure(:cache, e)
  end

  def check_queue
    unless defined?(SolidQueue::Process)
      return log_failure(:queue, StandardError.new("SolidQueue indisponível"))
    end

    if SolidQueue::Process.where("last_heartbeat_at > ?", 5.minutes.ago).exists?
      "ok"
    else
      log_failure(:queue, StandardError.new("nenhum processo SolidQueue com heartbeat nos últimos 5 min"))
    end
  rescue StandardError => e
    log_failure(:queue, e)
  end

  def log_failure(component, error)
    Rails.logger.error("[Healthz] #{component} falhou: #{error.class}: #{error.message}")
    "fail"
  end
end
