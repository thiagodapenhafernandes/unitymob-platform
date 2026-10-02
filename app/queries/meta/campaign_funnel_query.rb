module Meta
  # Junta o CRM ao Meta Ads: agrupa leads de origem Meta por campanha (id
  # resolvido pelo enriquecimento) e conta marcos do funil. O cruzamento com
  # investimento (tabela de insights) acontece no controller do painel.
  class CampaignFunnelQuery
    Result = Struct.new(:rows, keyword_init: true)

    CAMPAIGN_ID_SQL = <<~SQL.squish.freeze
      NULLIF(COALESCE(
        other_information ->> 'meta_campaign_id',
        other_information ->> 'campaign_id',
        attribution_data ->> 'campaign_id'
      ), '')
    SQL

    def initialize(tenant:, starts_at:, ends_at:)
      @tenant = tenant
      @starts_at = starts_at
      @ends_at = ends_at
    end

    def call
      leads = base_leads.to_a
      return Result.new(rows: []) if leads.empty?

      milestones = milestone_sets(leads.map(&:id))
      names = campaign_names(leads.map { |lead| campaign_id_for(lead) }.compact.uniq)

      grouped = leads.group_by { |lead| campaign_id_for(lead) }.reject { |key, _| key.nil? }
      rows = grouped.map do |campaign_id, row_leads|
        ids = row_leads.map(&:id)
        {
          campaign_id: campaign_id,
          campaign_name: names[campaign_id] || row_leads.filter_map { |lead| campaign_name_for(lead) }.first || campaign_id,
          leads: row_leads.size,
          qualified: row_leads.count { |lead| qualified?(lead) },
          visits: ids.count { |id| milestones[:visits].include?(id) },
          sales: ids.count { |id| milestones[:sales].include?(id) }
        }
      end

      Result.new(rows: rows.sort_by { |row| [-row[:sales], -row[:visits], -row[:leads]] })
    end

    private

    def base_leads
      @tenant.leads
             .where(created_at: @starts_at..@ends_at)
             .where("#{CAMPAIGN_ID_SQL} IS NOT NULL")
    end

    def campaign_id_for(lead)
      info = lead.other_information.to_h
      (info["meta_campaign_id"].presence || info["campaign_id"].presence ||
        lead.attribution_data.to_h["campaign_id"].presence)&.to_s
    end

    def campaign_name_for(lead)
      info = lead.other_information.to_h
      info["meta_campaign_name"].presence || info["campaign_name"].presence
    end

    def qualified?(lead)
      lead.broker_qualification_status == "qualified" || lead.manager_qualification_status == "qualified"
    end

    def milestone_sets(lead_ids)
      visit_ids = Appointment.where(tenant_id: @tenant.id, lead_id: lead_ids, kind: "visita", status: "realizado")
                             .distinct.pluck(:lead_id).to_set
      proposal_ids = Proposal.where(lead_id: lead_ids, status: "aceita").distinct.pluck(:lead_id).to_set
      won_stage_ids = @tenant.lead_pipeline_stages.where(stage_type: "won").pluck(:id).to_set
      concluido = Lead.status_value(:concluido, tenant: @tenant)

      stage_or_status_ids = Lead.where(id: lead_ids).pluck(:id, :lead_pipeline_stage_id, :status)
                                .select { |(_, stage_id, status)| won_stage_ids.include?(stage_id) || status == concluido }
                                .map(&:first).to_set

      { visits: visit_ids, sales: proposal_ids | stage_or_status_ids }
    end

    # Nome mais recente do snapshot (autoritativo); fallback para o que o lead guarda.
    def campaign_names(campaign_ids)
      MetaCampaignInsight.for_tenant(@tenant).where(campaign_id: campaign_ids)
                           .order(updated_at: :desc).pluck(:campaign_id, :campaign_name)
                           .each_with_object({}) { |(id, name), memo| memo[id] ||= name.presence }.compact
    end
  end
end
