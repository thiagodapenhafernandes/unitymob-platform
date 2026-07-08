# frozen_string_literal: true

# Rastreador interno de erros (substituto caseiro do Sentry). A persistência e
# o fingerprint vivem em ErrorEvent (app/models); aqui fica só a plumbing de
# captura, definida inline (padrão job_runtime_logging.rb) porque o autoloader
# principal (lib/ e app/) só é montado no finisher — depois destes initializers.
#
# Cobertura no Rails 7.1.6 (verificado no source do bundle):
# - Requests: o ActionDispatch::Executor reporta ao Rails.error apenas quando o
#   ShowExceptions trata a exceção (produção; e só para erros não mapeados em
#   rescue_responses). Em development o DebugExceptions renderiza a página de
#   debug antes e NADA é reportado — por isso o middleware abaixo, que também
#   enriquece o contexto (path/método/params filtrados/tenant).
# - Jobs: o ActiveJob 7.1 NÃO reporta ao Rails.error (só a partir do 7.2) — a
#   captura de jobs está no around_perform do ApplicationJob.
# - SolidQueue: on_thread_error usa Rails.error.report (coberto pelo subscriber).
# - Rails.error.handle/record manuais também caem no subscriber.
module ErrorTracking
  # Mesmo source usado pelo ActionDispatch::Executor — mapeia para "request".
  ACTION_DISPATCH_SOURCE = "application.action_dispatch"
  # Source emitido pelo around_perform do ApplicationJob — mapeia para "job".
  ACTIVE_JOB_SOURCE = "application.active_job"

  module_function

  # Traduz o source do ErrorReporter para o enum curto persistido no evento.
  def source_for(reporter_source)
    case reporter_source.to_s
    when ACTION_DISPATCH_SOURCE then "request"
    when ACTIVE_JOB_SOURCE then "job"
    else "manual"
    end
  end

  # Contexto enxuto da request: path/método/params filtrados (mesma lista de
  # Rails.application.config.filter_parameters) + tenant/usuário de Current.
  def request_context(env)
    request = ActionDispatch::Request.new(env)
    {
      # filtered_path (e não fullpath): a query string passa pela mesma lista
      # do filter_parameters — sem isso, reset_password_token e afins iriam
      # em texto plano pro banco e pra tela de erros.
      path: request.filtered_path.to_s[0, 300],
      method: request.request_method,
      params: filtered_params(request),
      admin_user_id: Current.admin_user&.id,
      tenant_id: Current.tenant&.id
    }.compact
  rescue StandardError
    {}
  end

  def filtered_params(request)
    request.filtered_parameters.except("controller", "action")
  rescue StandardError
    {}
  end

  # Assinante do Rails.error (ActiveSupport::ErrorReporter). handled: true
  # (Rails.error.handle) vira severity "warning".
  class Subscriber
    def report(error, handled:, severity:, context:, source: nil)
      ErrorEvent.record!(
        error,
        source: ErrorTracking.source_for(source),
        severity: handled ? "warning" : severity.to_s,
        context: (context || {}).merge(report_source: source.to_s)
      )
    rescue StandardError => e
      Rails.logger.error("[ERROR_TRACKER] subscriber falhou: #{e.class}: #{e.message}")
    end
  end

  # Middleware enxuto de captura de erros de request, logo abaixo do
  # DebugExceptions (perto do ShowExceptions). Reporta via Rails.error.report:
  # o reporter marca a exceção com @__rails_error_reported, então o report
  # posterior do Executor (produção) vira no-op — sem contagem dupla entre as
  # camadas. Re-lança SEMPRE.
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    rescue Exception => exception # rubocop:disable Lint/RescueException -- espelha o ShowExceptions; re-lança sempre
      track(exception, env)
      raise
    end

    private

    def track(exception, env)
      wrapper = ActionDispatch::ExceptionWrapper.new(nil, exception)
      # Exceções mapeadas para resposta (404/422 etc.) não são erro de
      # aplicação — mesmo critério do ShowExceptions (report_exception).
      return if wrapper.rescue_response?

      # unwrapped_exception: o mesmo objeto que o Executor reportaria (a causa
      # de um ActionView::Template::Error, por exemplo) — dedupe por identidade.
      Rails.error.report(
        wrapper.unwrapped_exception,
        handled: false,
        severity: :error,
        source: ErrorTracking::ACTION_DISPATCH_SOURCE,
        context: ErrorTracking.request_context(env)
      )
    rescue StandardError => e
      Rails.logger.error("[ERROR_TRACKER] middleware falhou: #{e.class}: #{e.message}")
    end
  end
end

Rails.application.config.middleware.insert_after ActionDispatch::DebugExceptions, ErrorTracking::Middleware
Rails.error.subscribe(ErrorTracking::Subscriber.new)
