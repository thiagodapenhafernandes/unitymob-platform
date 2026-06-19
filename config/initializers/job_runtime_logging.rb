# frozen_string_literal: true

module JobRuntimeLogging
  module_function

  def enabled?
    ENV.fetch("JOB_RUNTIME_LOGS", Rails.env.test? ? "0" : "1") == "1"
  end

  def stdout_enabled?
    ENV.fetch("JOBS_LOG_TO_STDOUT", "0") == "1"
  end

  def emit(level, message, stdout: stdout_enabled?)
    Rails.logger.public_send(level, message)
    $stdout.puts(message) if stdout
  end

  def job_details(job, include_arguments: false)
    details = [
      "class=#{job.class.name}",
      "queue=#{job.queue_name}",
      "job_id=#{job.job_id}"
    ]

    details << "provider_job_id=#{job.provider_job_id}" if job.provider_job_id.present?
    details << "executions=#{job.executions}" if job.respond_to?(:executions)
    details << "args=#{summarize_arguments(job.arguments)}" if include_arguments
    details.compact.join(" ")
  end

  def summarize_arguments(arguments)
    args = Array(arguments)
    return "[]" if args.empty?

    limit = 4
    summarized = args.first(limit).map { |argument| summarize_argument(argument) }
    summarized << "...(+#{args.size - limit})" if args.size > limit
    "[#{summarized.join(', ')}]"
  rescue StandardError => error
    "[unavailable: #{error.class.name}]"
  end

  def summarize_argument(argument)
    if argument.respond_to?(:to_global_id) && argument.respond_to?(:id)
      return "#{argument.class.name}##{argument.id}"
    end

    case argument
    when Hash
      keys = argument.keys.first(6).map(&:to_s).join(",")
      suffix = argument.keys.size > 6 ? ",..." : ""
      "Hash(keys=#{keys}#{suffix})"
    when Array
      "Array(size=#{argument.size})"
    when String
      "String(#{argument.bytesize}b)"
    when Numeric, Symbol, TrueClass, FalseClass, NilClass
      argument.inspect
    else
      argument.class.name
    end
  end

  def exception_details(payload)
    exception = payload[:exception]
    return nil unless exception

    "#{exception[0]}: #{exception[1]}"
  end
end

if JobRuntimeLogging.enabled?
  ActiveSupport::Notifications.subscribe("enqueue.active_job") do |*, payload|
    job = payload[:job]
    JobRuntimeLogging.emit(:info, "[jobs] enqueued #{JobRuntimeLogging.job_details(job)}")
  end

  ActiveSupport::Notifications.subscribe("enqueue_at.active_job") do |*, payload|
    job = payload[:job]
    JobRuntimeLogging.emit(:info, "[jobs] scheduled #{JobRuntimeLogging.job_details(job)}")
  end

  ActiveSupport::Notifications.subscribe("perform_start.active_job") do |*, payload|
    job = payload[:job]
    JobRuntimeLogging.emit(:info, "[jobs] started #{JobRuntimeLogging.job_details(job, include_arguments: true)}")
  end

  ActiveSupport::Notifications.subscribe("perform.active_job") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    job = event.payload[:job]
    error = JobRuntimeLogging.exception_details(event.payload)
    details = "#{JobRuntimeLogging.job_details(job)} duration=#{event.duration.round(1)}ms"

    if error
      JobRuntimeLogging.emit(:error, "[jobs] failed #{details} error=#{error}")
    else
      JobRuntimeLogging.emit(:info, "[jobs] finished #{details}")
    end
  end

  ActiveSupport::Notifications.subscribe("discard.active_job") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    job = event.payload[:job]
    error = JobRuntimeLogging.exception_details(event.payload)
    details = "#{JobRuntimeLogging.job_details(job)} duration=#{event.duration.round(1)}ms"
    JobRuntimeLogging.emit(:warn, "[jobs] discarded #{details} error=#{error}")
  end

  ActiveSupport::Notifications.subscribe("enqueue_retry.active_job") do |*, payload|
    job = payload[:job]
    wait = payload[:wait]
    error = payload[:error]
    message = "[jobs] retry_scheduled #{JobRuntimeLogging.job_details(job)} wait=#{wait.inspect}"
    message += " error=#{error.class}: #{error.message}" if error
    JobRuntimeLogging.emit(:warn, message)
  end

  ActiveSupport::Notifications.subscribe("retry_stopped.active_job") do |*, payload|
    job = payload[:job]
    error = payload[:error]
    message = "[jobs] retry_stopped #{JobRuntimeLogging.job_details(job)}"
    message += " error=#{error.class}: #{error.message}" if error
    JobRuntimeLogging.emit(:error, message)
  end
end
