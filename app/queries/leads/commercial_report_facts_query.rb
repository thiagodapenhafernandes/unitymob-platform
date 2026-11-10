module Leads
  # Consulta em lote; datas desconhecidas permanecem vazias, sem usar updated_at como atendimento.
  class CommercialReportFactsQuery
    CONTACT_KINDS = %w[whatsapp_out instagram_out email_out appointment_done proposal_sent].freeze

    def initialize(tenant:, leads:, starts_at: nil, ends_at: nil)
      @tenant, @leads = tenant, leads.index_by(&:id)
      raise ArgumentError, 'Leads de outra conta' unless leads.all? { |lead| lead.tenant_id == tenant.id }
      @window = starts_at..ends_at
      @facts = @leads.transform_values { {received_at: nil, first_attended_at: nil, visits: 0, pool: false} }
    end

    def call
      return @facts if @leads.empty?
      load_assignments
      load_contacts
      load_visits
      @facts
    end

    private

    def activities
      LeadActivity.where(tenant_id: @tenant.id, lead_id: @leads.keys)
    end

    def matching_owner?(lead, user_id, name = nil)
      return false unless lead.admin_user_id
      user_id.present? ? user_id.to_s == lead.admin_user_id.to_s : name.present? && name == lead.admin_user&.name
    end

    def received(lead_id, at)
      @facts[lead_id][:received_at] = [@facts[lead_id][:received_at], at].compact.max
    end

    def load_assignments
      pool = Dashboard::LeadPerformancePeriodQuery.new(scope: @tenant.leads.where(id: @leads.keys), starts_at: nil, ends_at: nil).pool_acceptances.where(tenant_id: @tenant.id)
      pool.pluck(:id, :lead_id).each { |_, lead_id| @facts[lead_id][:pool] = true }
      events = activities.where(kind: %w[distributed assigned_directly]).or(activities.where(id: pool.select(:id)))
      events.pluck(:lead_id, :created_at, Arel.sql("metadata ->> 'admin_user_id'"), Arel.sql("metadata ->> 'by'")).each do |id, at, actor, name|
        received(id, at) if matching_owner?(@leads.fetch(id), actor, name)
      end
      LeadAuditLog.where(tenant_id: @tenant.id, lead_id: @leads.keys)
        .where("changeset ? 'admin_user_id'")
        .pluck(:lead_id, :created_at, Arel.sql("changeset #>> '{admin_user_id,after}'")).each do |id, at, actor|
          received(id, at) if matching_owner?(@leads.fetch(id), actor)
        end
    end

    def contact(lead_id, at, actor, name = nil)
      return unless matching_owner?(@leads.fetch(lead_id), actor, name)
      boundary = @facts[lead_id][:received_at]
      return if boundary && at < boundary
      @facts[lead_id][:first_attended_at] = [@facts[lead_id][:first_attended_at], at].compact.min
    end

    def load_contacts
      events = activities.human_operational.where(kind: CONTACT_KINDS)
        .or(activities.human_operational.contact_attempts)
      events.pluck(:lead_id, :created_at, Arel.sql("metadata ->> 'admin_user_id'"), Arel.sql("metadata ->> 'by'")).each do |id, at, actor, name|
        contact(id, at, actor, name)
      end
      InstagramMessage.joins(:lead).where(leads: {tenant_id: @tenant.id}, lead_id: @leads.keys, direction: 'outbound').where.not(sent_by_admin_user_id: nil)
        .pluck(:lead_id, :occurred_at, :sent_by_admin_user_id).each { |id, at, actor| contact(id, at, actor) }
      WhatsappMessage.joins(:whatsapp_conversation)
        .where(tenant_id: @tenant.id, whatsapp_conversations: {tenant_id: @tenant.id, lead_id: @leads.keys}, direction: 'outbound', status: %w[sent delivered read])
        .where.not(admin_user_id: nil)
        .pluck(Arel.sql('whatsapp_conversations.lead_id'), :sent_at, :created_at, :admin_user_id).each do |id, sent_at, created_at, actor|
          contact(id, sent_at || created_at, actor)
        end
      Appointment.where(tenant_id: @tenant.id, lead_id: @leads.keys, kind: 'visita', status: 'realizado')
        .pluck(:lead_id, :starts_at, :admin_user_id).each { |id, at, actor| contact(id, at, actor) }
    end

    def load_visits
      Appointment.where(tenant_id: @tenant.id, lead_id: @leads.keys, kind: 'visita', status: 'realizado', starts_at: @window)
        .pluck(:lead_id, :starts_at, :admin_user_id).each do |id, at, actor|
          boundary = @facts[id][:received_at]
          @facts[id][:visits] += 1 if matching_owner?(@leads.fetch(id), actor) && (!boundary || at >= boundary)
        end
    end
  end
end
