module InterestIntelligence
  # Leitura operacional, sem alterar etapa, tarefas ou histórico do lead.
  class Journey
    def self.call(lead)
      new(lead).call
    end

    def initialize(lead)
      @lead = lead
    end

    def call
      result = reading
      result.merge(
        share_events: share_events.includes(:habitation).order(created_at: :desc).limit(100).to_a,
        activities: activities, next_activity: result[:classification] == "encerrado" ? nil : next_activity,
        last_navigation_at: [navigation.maximum(:occurred_at), share_events.where(event_type: %w[property_opened collection_opened interest_created interest_repeated]).maximum(:created_at)].compact.max,
        viewed_count: viewed_ids.size,
        declared_count: share_events.where(event_type: %w[interest_created interest_repeated]).distinct.count(:habitation_id),
        favorite_properties: favorite_properties,
        favorite_observed: @lead.public_navigation_sessions.where(tenant_id: @lead.tenant_id).where("metadata ? 'favorite_property_ids'").exists?,
        first_navigation: navigation.order(:occurred_at, :id).first,
        last_navigation: navigation.order(occurred_at: :desc, id: :desc).first
      )
    end

    private

    def reading
      stage_type = @lead.lead_pipeline_stage&.stage_type
      won = @lead.closed_at.present? || stage_type == "won" || @lead.status == Lead.status_value(:concluido, tenant: @lead.tenant)
      lost = @lead.archived_at.present? || %w[lost archived].include?(stage_type) || @lead.status == Lead.status_value(:descartado, tenant: @lead.tenant)
      if won || lost
        ended_at = @lead.closed_at || @lead.archived_at
        new_activity = ended_at && (navigation.where("occurred_at > ?", ended_at).exists? || share_events.where(event_type: %w[property_opened collection_opened interest_created interest_repeated]).where("created_at > ?", ended_at).exists?)
        return state("encerrado", new_activity ? "Avaliar retomada" : won ? "Negócio fechado" : "Encerrado sem negócio", new_activity ? :amber : won ? :green : :gray,
          won ? "O ciclo comercial foi concluído." : "Atendimento encerrado: #{@lead.archive_reason&.name.presence || 'motivo não informado'}.",
          new_activity ? "Há navegação após o encerramento. Avalie uma nova necessidade; o ciclo anterior permanece encerrado." : "A origem, a navegação e o atendimento permanecem disponíveis para consulta.",
          "O encerramento registrado prevalece sobre a temperatura. Novos acessos não reabrem o atendimento automaticamente.")
      end

      if last_contact&.meta("contact_result") == "sem_interesse" && (!proposal || last_contact.created_at >= proposal.updated_at)
        return state("frio", "Revisar interesse", :gray, "O último contato registrou ausência de interesse.", "Revise o contexto e registre um encerramento com motivo, se aplicável.", "Uma resposta negativa do cliente prevalece sobre cliques anteriores.")
      end
      if last_contact&.meta("contact_result") == "retornar_depois" && next_activity && next_activity[:at] > Time.current
        return state("retorno_combinado", "Retorno combinado", :amber, "Há um retorno futuro registrado após o pedido do cliente.", "Respeite o prazo combinado; ausência de navegação não é perda.", "Pedido de retorno e compromisso futuro são tratados separadamente da atividade digital.")
      end
      if proposal
        return state("quente", "Em negociação", :red, "Proposta #{proposal.status_label.downcase}#{proposal.habitation ? " · imóvel #{proposal.habitation.codigo}" : ''}.", "Acompanhe a decisão e os compromissos registrados. Envio não significa aceite ou fechamento.", "Existe uma proposta enviada, visualizada ou aceita e ainda válida. A leitura não depende de novos cliques.")
      end
      if visit
        return state("quente", "Visita agendada", :red, "Há uma visita agendada#{visit.habitation ? " ao imóvel #{visit.habitation.codigo}" : ''}.", "Acompanhe o compromisso. Agendamento não comprova realização ou confirmação do cliente.", "O compromisso comercial prevalece sobre a ausência de navegação.")
      end
      if @lead.appointments.where(tenant_id: @lead.tenant_id, kind: "visita", status: "realizado").where("starts_at >= ?", 14.days.ago).exists?
        return state("quente", "Visita realizada", :red, "Há uma visita realizada nos últimos 14 dias.", "Confira o resultado da visita e o próximo passo antes de preparar novas opções.", "A visita realizada é evidência comercial; não garante intenção atual nem fechamento.")
      end
      if share_events.where(event_type: %w[interest_created interest_repeated]).where("created_at >= ?", 7.days.ago).exists?
        return state("quente", "Quente · interesse declarado", :red, "Foi registrado interesse em um imóvel compartilhado.", "Confirme a necessidade com o cliente e a disponibilidade do imóvel.", "Manifestação explícita registrada nos últimos 7 dias. Não é probabilidade de compra; links podem ser encaminhados.")
      end
      if last_contact&.meta("contact_result") == "falou_com_cliente" && last_contact.created_at >= 14.days.ago
        return state("morno", "Morno · contato realizado", :amber, "O corretor registrou uma conversa com o cliente.", "Use o resultado do contato para refinar as opções e acompanhar o próximo compromisso.", "Uma conversa registrada oferece contexto comercial. Preferências, orçamento e intenção só são confirmados pelo conteúdo do atendimento.")
      end
      if navigation.where(name: %w[property_view property_search property_favorite_added]).where("occurred_at >= ?", 14.days.ago).exists? ||
         share_events.where(event_type: %w[property_opened collection_opened]).where("created_at >= ?", 14.days.ago).exists?
        return state("morno", "Morno · pesquisa recente", :amber, "Há pesquisa ou favoritos registrados recentemente.", "Confira as preferências e o atendimento antes do próximo contato.", "Atividade observada nos últimos 14 dias. Favoritar ou visualizar não comprova capacidade financeira ou decisão de compra.")
      end
      if navigation.exists? || share_events.where(event_type: %w[property_opened collection_opened interest_created interest_repeated]).exists? || last_contact
        return state("frio", "Frio · sem sinais recentes", :gray, "Não há sinal recente suficiente para confirmar avanço.", "Revise o histórico e o próximo retorno. Tentativas do corretor não aumentam o interesse do cliente.", "Sem avanço comercial ou atividade digital recente identificados. Não significa desistência e não encerra o lead.")
      end
      state("sem_sinais", "Aguardando sinais", :gray, "Ainda não há sinais suficientes vinculados ao lead.", "Converse com o cliente e compartilhe imóveis pelo sistema para reunir preferências.", "Ausência de histórico não é evidência de desinteresse.")
    end

    def state(classification, label, tone, headline, description, method)
      { classification: classification, label: label, tone: tone, headline: headline, description: description, method: method }
    end

    def navigation
      @navigation ||= @lead.public_navigation_events.where(tenant_id: @lead.tenant_id)
    end

    def share_events
      @share_events ||= AiPropertyShareAuditEvent.where(tenant_id: @lead.tenant_id).where(
        "lead_id = :lead OR ai_property_share_collection_id IN (:collections)",
        lead: @lead.id, collections: @lead.ai_property_share_collections.select(:id)
      )
    end

    def viewed_ids
      navigation.where(name: "property_view").where.not(habitation_id: nil).distinct.pluck(:habitation_id) |
        share_events.where(event_type: "property_opened").where.not(habitation_id: nil).distinct.pluck(:habitation_id)
    end

    def favorite_properties
      @favorite_properties ||= Habitation.for_tenant(@lead.tenant_id).where(id: FavoriteSync.property_ids_for(@lead)).order(:codigo).to_a
    end

    def activities
      @activities ||= @lead.activities.where(tenant_id: @lead.tenant_id).where.not(source_category: "automation").recent.limit(12).to_a
    end

    def last_contact
      @last_contact ||= @lead.activities.where(tenant_id: @lead.tenant_id).contact_attempts.recent.first
    end

    def proposal
      @proposal ||= @lead.proposals.where(status: %w[enviada visualizada aceita]).where("validade IS NULL OR validade >= ?", Date.current).includes(:habitation).order(updated_at: :desc).first
    end

    def visit
      @visit ||= @lead.appointments.where(tenant_id: @lead.tenant_id, kind: "visita", status: "agendado").where("starts_at >= ?", Time.current).includes(:habitation).order(:starts_at).first
    end

    def next_activity
      return @next_activity if defined?(@next_activity)

      task = @lead.tasks.where(tenant_id: @lead.tenant_id, status: "pendente").where.not(due_at: nil).includes(:admin_user).order(:due_at).first
      appointment = @lead.appointments.where(tenant_id: @lead.tenant_id, status: "agendado").includes(:admin_user).order(:starts_at).first
      @next_activity = [
        (task && { title: task.title, at: task.due_at, owner: task.admin_user&.name }),
        (appointment && { title: appointment.title, at: appointment.starts_at, owner: appointment.admin_user&.name })
      ].compact.min_by { |item| item[:at] }
    end
  end
end
