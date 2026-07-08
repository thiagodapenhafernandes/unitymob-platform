class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # Rastreador interno de erros: o ActiveJob 7.1 não reporta falhas ao
  # Rails.error (só a partir do 7.2), então a captura de jobs acontece aqui.
  # Re-lança SEMPRE — retry_on/discard_on e o FailedExecution do SolidQueue
  # dependem da exceção subir.
  # Reporta via Rails.error (e não ErrorEvent.record! direto) de propósito:
  # o reporter marca a exceção com @__rails_error_reported, o que transforma o
  # report duplicado do on_thread_error do SolidQueue em no-op — sem isso a
  # falha final contaria 2x e o contexto do job seria sobrescrito.
  around_perform do |job, block|
    block.call
  rescue StandardError => exception
    Rails.error.report(
      exception,
      handled: false,
      severity: :error,
      source: "application.active_job",
      context: {
        job_class: job.class.name,
        queue: job.queue_name,
        executions: job.executions,
        job_args: (JobRuntimeLogging.summarize_arguments(job.arguments) if defined?(JobRuntimeLogging))
      }.compact
    )
    raise
  end
end
