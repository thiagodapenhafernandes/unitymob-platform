module Admin::ComercialHelper
  # --- Timeline unificada ---------------------------------------------------
  # Mapeia um LeadActivity em ícone + cor + texto para o feed cronológico.
  TIMELINE_MAP = {
    "created"            => { icon: "bi-stars",            color: "blue",  label: "Lead criado" },
    "distributed"        => { icon: "bi-diagram-3",        color: "blue",  label: "Distribuído" },
    "accepted"           => { icon: "bi-check2-circle",    color: "green", label: "Aceito pelo corretor" },
    "rejected"           => { icon: "bi-x-circle",         color: "red",   label: "Recusado" },
    "status_change"      => { icon: "bi-arrow-left-right", color: "gray",  label: "Etapa alterada" },
    "comment"            => { icon: "bi-chat-left-text",   color: "gray",  label: "Comentário" },
    "note"               => { icon: "bi-pencil-square",    color: "gray",  label: "Contato registrado" },
    "task_created"       => { icon: "bi-check2-square",    color: "amber", label: "Tarefa criada" },
    "task_completed"     => { icon: "bi-check-circle-fill",color: "green", label: "Tarefa concluída" },
    "appointment_created"=> { icon: "bi-calendar-plus",    color: "blue",  label: "Compromisso agendado" },
    "appointment_done"   => { icon: "bi-calendar-check",   color: "green", label: "Compromisso realizado" },
    "proposal_created"   => { icon: "bi-file-earmark-text",color: "gray",  label: "Proposta criada" },
    "proposal_sent"      => { icon: "bi-send",             color: "blue",  label: "Proposta enviada" },
    "proposal_viewed"    => { icon: "bi-eye",              color: "amber", label: "Proposta visualizada" },
    "proposal_aceita"    => { icon: "bi-hand-thumbs-up",   color: "green", label: "Proposta aceita" },
    "proposal_recusada"  => { icon: "bi-hand-thumbs-down", color: "red",   label: "Proposta recusada" },
    "whatsapp_in"        => { icon: "bi-whatsapp",         color: "green", label: "Mensagem recebida" },
    "whatsapp_out"       => { icon: "bi-whatsapp",         color: "blue",  label: "Mensagem enviada" },
    "automation"         => { icon: "bi-lightning-charge", color: "amber", label: "Automação" }
  }.freeze

  def timeline_entry(activity)
    base = TIMELINE_MAP[activity.kind] || { icon: "bi-dot", color: "gray", label: activity.kind.to_s.humanize }
    detail = timeline_detail(activity)
    base.merge(detail: detail, at: activity.created_at)
  end

  def timeline_detail(activity)
    meta = activity.metadata.is_a?(Hash) ? activity.metadata : {}
    case activity.kind
    when "note"        then meta["body"].presence
    when "task_created", "task_completed", "appointment_created", "appointment_done" then meta["title"].presence
    when "status_change" then [meta["from"], meta["to"]].compact.join(" → ").presence
    else nil
    end
  end

  # --- Barra de funil -------------------------------------------------------
  def funnel_progress(lead, statuses)
    current = Lead.status_value(lead.status)
    idx = statuses.index(current)
    statuses.each_with_index.map do |status, i|
      state = if idx.nil? then (status == current ? :current : :upcoming)
              elsif i < idx then :done
              elsif i == idx then :current
              else :upcoming
              end
      { status: status, state: state }
    end
  end

  # --- SLA (tempo no status atual ~ idade do lead) --------------------------
  def lead_sla(lead)
    hours = ((Time.current - lead.updated_at) / 3600.0)
    if hours < 24 then { color: "green", label: time_ago_in_words(lead.updated_at) + " atrás" }
    elsif hours < 72 then { color: "amber", label: time_ago_in_words(lead.updated_at) + " sem ação" }
    else { color: "red", label: time_ago_in_words(lead.updated_at) + " sem ação" }
    end
  end

  # --- Badges ---------------------------------------------------------------
  def proposal_badge_color(proposal)
    case proposal.status
    when "aceita" then "green"
    when "recusada", "expirada" then "red"
    when "visualizada" then "amber"
    when "enviada" then "blue"
    else "gray"
    end
  end

  def task_badge(task)
    if task.concluida? then { color: "green", label: "Concluída" }
    elsif task.atrasada? then { color: "red", label: "Atrasada" }
    elsif task.due_at.present? then { color: "amber", label: l(task.due_at, format: :short) }
    else { color: "gray", label: "Sem prazo" }
    end
  end

  def brl(value)
    number_to_currency(value.to_f, unit: "R$ ", separator: ",", delimiter: ".", format: "%u%n")
  end
end
