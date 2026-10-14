module Leads
  # Read-only evidence projection; commercial status alone never proves a milestone.
  class Journey
    LIMIT = 10

    def initialize(lead)
      @lead = lead
    end

    def milestones
      @milestones ||= [
        { key: :entry, title: "Entrada", state: "Registrada", confirmed: true, evidence: [
          { source: "Lead ##{@lead.id}", at: @lead.created_at, actor: nil,
            detail: "Cadastro criado · origem: #{@lead.origin.presence || 'Não informada'}" }
        ] },
        activity_milestone(:distribution, "Distribuição", "distributed", "Registrada"),
        activity_milestone(:acceptance, "Aceite", "accepted", "Registrado"),
        contact_milestone,
        appointment_milestone,
        proposal_milestone,
        activity_milestone(:closing, "Fechamento", "deal_closed", "Declarado no CRM")
      ]
    end

    def presentation
      rows = milestones.map do |milestone|
        point_evidence = milestone[:evidence].find { |e| e[:confirmed] != false }
        milestone.merge(date_label: point_evidence ? I18n.l(point_evidence[:at], format: :short) : nil, lane: milestone[:key] == :entry ? 2 : milestone[:key] == :distribution ? 1 : 0,
          evidence: milestone[:evidence].map { |e| e.merge(at: e[:at].iso8601, date_label: I18n.l(e[:at], format: :short)) })
      end
      contact = rows.find { |m| m[:key] == :contact }
      acceptance = rows.find { |m| m[:key] == :acceptance }
      closing = rows.find { |m| m[:key] == :closing }
      {
        milestones: rows, lead: { name: @lead.display_name, owner: safe_actor(@lead.admin_user) || "Não informado",
          origin: @lead.origin.presence || "Não informada", property: @lead.property_id ? "Imóvel ##{@lead.property_id}" : "Não vinculado" },
        initial: contact[:confirmed] ? :visit : :contact,
        summary: closing[:confirmed] ? "Fechamento declarado no CRM; consulte as evidências de cada marco." : contact[:confirmed] ? "Contato humano confirmado; acompanhe os próximos marcos comerciais." : acceptance[:confirmed] ? "O lead foi aceito; o contato humano continua sem confirmação." : "Acompanhe a entrada e os marcos ainda sem confirmação.",
        waiting: !contact[:confirmed] && !closing[:confirmed],
        entry_seconds: [Time.current - @lead.created_at, 0].max.to_i,
        acceptance_seconds: acceptance[:evidence].first ? [Time.current - Time.iso8601(acceptance[:evidence].first[:at]), 0].max.to_i : nil
      }
    end

    private

    def activities
      @lead.activities.where(tenant_id: @lead.tenant_id)
    end

    def activity_milestone(key, title, kind, confirmed_state)
      rows = activities.where(kind: kind).order(created_at: :desc, id: :desc).limit(LIMIT)
      { key: key, title: title, confirmed: rows.any?, state: rows.any? ? confirmed_state : "Sem evidência registrada",
        evidence: rows.map { |row| activity_evidence(row) } }
    end

    def activity_evidence(row)
      { source: "Histórico ##{row.id}", at: row.created_at, actor: row.meta(:by).presence || row.meta(:admin_user_name),
        detail: [row.meta(:body), ("Regra: #{row.meta(:rule_name).presence || row.meta(:rule_id)}" if row.meta(:rule_id) || row.meta(:rule_name)),
                 ("Responsável ##{row.meta(:admin_user_id)}" if row.meta(:admin_user_id))].compact.join(" · ") }
    end

    def contact_milestone
      scope = activities.human_operational.contact_attempts
      confirmed = scope.where("metadata ->> 'contact_result' = ?", "falou_com_cliente").order(created_at: :asc, id: :asc).first
      rows = with_confirmation(scope.order(created_at: :desc, id: :desc).limit(LIMIT), confirmed)
      { key: :contact, title: "Contato humano", confirmed: confirmed.present?, state: confirmed ? "Contato confirmado" : rows.any? ? "Tentativas registradas; contato não confirmado" : "Sem evidência registrada",
        evidence: rows.map do |row|
          activity_evidence(row).merge(confirmed: row.meta(:contact_result) == "falou_com_cliente", detail: [LeadActivity::CONTACT_KIND_LABELS[row.meta(:contact_kind)],
            LeadActivity::CONTACT_RESULT_LABELS[row.meta(:contact_result)], row.meta(:body)].compact.join(" · "))
        end }
    end

    def appointment_milestone
      scope = @lead.appointments.where(tenant_id: @lead.tenant_id, kind: "visita")
      scope = scope.includes(:admin_user)
      performed = scope.where(status: "realizado").order(starts_at: :desc, id: :desc).first
      rows = with_confirmation(scope.order(starts_at: :desc, id: :desc).limit(LIMIT), performed)
      { key: :visit, title: "Visita", confirmed: performed.present?, state: performed ? "Visita registrada como realizada" : scope.where(status: "agendado").exists? ? "Agendada; realização pendente" : "Sem visita realizada registrada",
        evidence: rows.map do |row|
          { source: "Agenda ##{row.id}", confirmed: row.status == "realizado", at: row.starts_at, actor: safe_actor(row.admin_user),
            detail: [row.title, "Situação: #{row.status}", "Data/hora agendada",
                     ("Imóvel ##{row.habitation_id}" if row.habitation_id)].compact.join(" · ") }
        end }
    end

    def proposal_milestone
      scope = @lead.proposals
      scope = scope.includes(:admin_user)
      sent = scope.where.not(sent_at: nil).order(sent_at: :desc, id: :desc).first
      rows = with_confirmation(scope.order(created_at: :desc, id: :desc).limit(LIMIT), sent)
      { key: :proposal, title: "Proposta", confirmed: sent.present?, state: sent ? "Envio registrado" : scope.exists? ? "Proposta cadastrada; envio sem evidência" : "Sem evidência registrada",
        evidence: rows.map do |row|
          { source: "Proposta ##{row.id}", confirmed: row.sent_at.present?, at: row.sent_at || row.created_at, actor: safe_actor(row.admin_user),
            detail: [row.status_label, row.sent_at ? "Data/hora de envio" : "Data/hora de criação; não comprova envio",
                     ("Visualizada em #{I18n.l(row.viewed_at, format: :short)}" if row.viewed_at),
                     ("Decisão em #{I18n.l(row.responded_at, format: :short)}" if row.responded_at)].compact.join(" · ") }
        end }
    end

    def with_confirmation(rows, confirmed)
      rows = rows.to_a
      rows.unshift(confirmed) if confirmed && rows.none? { |row| row.id == confirmed.id }
      rows
    end

    def safe_actor(user)
      user&.tenant_id == @lead.tenant_id ? user.name : nil
    end
  end
end
