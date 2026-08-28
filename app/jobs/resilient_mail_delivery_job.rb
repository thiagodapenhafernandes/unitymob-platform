class ResilientMailDeliveryJob < ActionMailer::MailDeliveryJob
  TRANSIENT_SMTP_ERRORS = [
    Net::OpenTimeout,
    Net::ReadTimeout,
    Timeout::Error,
    Errno::ECONNRESET,
    Errno::ECONNREFUSED,
    EOFError,
    IOError
  ].freeze

  retry_on(*TRANSIENT_SMTP_ERRORS, wait: :polynomially_longer, attempts: 5) do |job, error|
    job.report_final_delivery_failure(error)
    raise error
  end

  def report_final_delivery_failure(error)
    Rails.error.report(
      error,
      handled: false,
      severity: :error,
      source: ErrorTracking::ACTIVE_JOB_SOURCE,
      context: delivery_context
    )
  end

  private

  def delivery_context
    mailer, mail_method, delivery_method, payload = arguments
    params = extract_params(payload)

    {
      job_class: self.class.name,
      queue: queue_name,
      executions: executions,
      mailer: mailer,
      mail_method: mail_method,
      delivery_method: delivery_method,
      tenant_id: tenant_id_from(params),
      lead_id: record_id_from(params, :lead),
      admin_user_id: record_id_from(params, :corretor)
    }.compact
  end

  def extract_params(payload)
    return {} unless payload.respond_to?(:[])

    payload[:params] || payload["params"] || {}
  end

  def tenant_id_from(params)
    tenant = params[:tenant] || params["tenant"]
    return tenant.id if tenant.respond_to?(:id)

    lead = params[:lead] || params["lead"]
    return lead.tenant_id if lead.respond_to?(:tenant_id)

    corretor = params[:corretor] || params["corretor"]
    corretor.tenant_id if corretor.respond_to?(:tenant_id)
  end

  def record_id_from(params, key)
    record = params[key] || params[key.to_s]
    record.id if record.respond_to?(:id)
  end
end
