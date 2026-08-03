module Admin::UserActivitySessionsHelper
  def operational_duration_label(seconds)
    total = seconds.to_i
    hours = total / 3600
    minutes = (total % 3600) / 60

    return "#{hours}h #{minutes}min" if hours.positive?
    return "#{minutes}min" if minutes.positive?

    "#{total}s"
  end

  def operational_event_count(counts, session, *names)
    names.sum { |name| counts[[session.id, name]].to_i }
  end

  def operational_event_payload(payload)
    hash = payload.is_a?(Hash) ? payload : {}
    return if hash.blank?

    JSON.pretty_generate(hash)
  end
end
