module Dashboard
  class CampaignPerformanceQuery
    Result = Struct.new(
      :rows,
      :period_label,
      keyword_init: true
    )

    CHANNEL_LABELS = Dashboard::LeadAcquisitionQuery::CHANNEL_LABELS.merge(
      "whatsapp" => "WhatsApp",
      "site" => "Site",
      "cadastro_manual" => "Cadastro manual"
    ).freeze

    def initialize(scope:, tenant:, starts_at:, ends_at:, period_label:, limit: 8)
      @scope = scope.where(leads: { created_at: starts_at..ends_at })
      @tenant = tenant
      @period_label = period_label
      @limit = limit
    end

    def call
      Result.new(rows: campaign_rows, period_label: @period_label)
    end

    private

    def campaign_rows
      leads = @scope.includes(:admin_user).order("leads.created_at DESC").to_a
      return [] if leads.empty?

      context = build_context(leads)
      grouped = leads.group_by { |lead| campaign_key(lead, context) }.reject { |key, _row_leads| key.nil? }

      grouped.map do |key, row_leads|
        build_row(key, row_leads, context)
      end.sort_by do |row|
        [-row[:closed_count].to_i, -row[:opportunity_count].to_i, -row[:contacted_count].to_i, -row[:attended_count].to_i, -row[:total].to_i, row[:title].to_s]
      end.first(@limit)
    end

    def build_context(leads)
      lead_ids = leads.map(&:id)
      attempts = LeadActivity.human_operational.contact_attempts
        .where(lead_id: lead_ids)
        .order(created_at: :desc)
        .group_by(&:lead_id)
      attendance_events = LeadActivity
        .where(lead_id: lead_ids, kind: %w[accepted secure_link_accessed])
        .order(:created_at)
        .to_a
      attended_at = attended_at_by_lead(attendance_events)
      visit_ids = Appointment.where(kind: "visita", lead_id: lead_ids).distinct.pluck(:lead_id).index_with(true)
      proposal_ids = Proposal.where.not(status: "rascunho").where(lead_id: lead_ids).distinct.pluck(:lead_id).index_with(true)
      closed_ids = leads.select { |lead| Lead.status_value(lead.status) == Lead.status_value(:concluido) }.map(&:id).index_with(true)

      {
        attempts: attempts,
        attended_at: attended_at,
        visit_ids: visit_ids,
        proposal_ids: proposal_ids,
        closed_ids: closed_ids,
        site_events: site_events_by_lead(lead_ids),
        meta_form_names: meta_form_names(leads)
      }
    end

    def attended_at_by_lead(events)
      events.each_with_object({}) do |event, result|
        next unless attendance_event?(event)

        result[event.lead_id] ||= event.created_at
      end
    end

    def attendance_event?(activity)
      return true if activity.kind == "accepted"

      activity.kind == "secure_link_accessed" &&
        (activity.meta("contact").to_s.in?(%w[attend whatsapp]) || activity.meta("action_type").to_s.in?(%w[attend phone]))
    end

    def site_events_by_lead(lead_ids)
      return {} if lead_ids.empty? || !defined?(SeoConversionEvent)

      SeoConversionEvent
        .joins(:lead)
        .where(leads: { tenant_id: @tenant.id }, lead_id: lead_ids, event_type: "lead_created")
        .select("DISTINCT ON (seo_conversion_events.lead_id) seo_conversion_events.*")
        .order(:lead_id, :occurred_at, :id)
        .includes(:habitation)
        .index_by(&:lead_id)
    end

    def meta_form_names(leads)
      references = leads.to_h { |lead| [lead.id, meta_form_reference(lead)] }
      form_ids = references.values.filter_map { |reference| reference["form_id"].presence }.map(&:to_s).uniq
      return {} if form_ids.empty?

      forms = MetaLeadForm.joins(meta_facebook_page: :user_meta_integration)
        .where(user_meta_integrations: { tenant_id: @tenant.id }, form_id: form_ids)
        .pluck("meta_facebook_pages.page_id", :form_id, :name)

      leads.to_h do |lead|
        reference = references.fetch(lead.id)
        names = forms.select do |page_id, form_id, _name|
          form_id == reference["form_id"].to_s &&
            (reference["page_id"].blank? || page_id == reference["page_id"].to_s)
        end.map(&:last).uniq
        [lead.id, names.one? ? names.first : nil]
      end
    end

    def meta_form_reference(lead)
      info = lead.other_information.to_h
      return { "form_id" => info["meta_form_id"], "page_id" => info["meta_page_id"] } if info["meta_form_id"].present?

      candidates = [lead.attribution_data.to_h["facebook"]]
      %w[external_lead_payload c2s_payload data].each do |key|
        payload = info[key]
        candidates << payload["facebook_attributes"] if payload.is_a?(Hash)
      end
      candidates.find { |item| item.is_a?(Hash) && item["form_id"].present? } || {}
    end

    def campaign_key(lead, context)
      info = lead.other_information.to_h
      attribution = lead.attribution_data.to_h
      campaign = campaign_name(info, attribution)
      form = form_name(lead, info, attribution, context)
      channel = normalized_channel(lead)

      if meta_lead?(lead, info, attribution)
        ["meta", campaign.presence || "Meta Ads sem campanha", form.presence || "Formulário não identificado"]
      elsif site_lead?(lead, channel, context[:site_events][lead.id])
        site_key(lead, channel, context[:site_events][lead.id])
      elsif campaign.present?
        ["channel", campaign, form.presence || channel_label(channel)]
      elsif whatsapp_lead?(lead, channel)
        ["unknown", "Origem sem detalhe", "Entrada sem página, campanha ou formulário registrado"]
      elsif lead.origin.to_s.parameterize(separator: "_") == "cadastro_manual"
        ["manual", "Cadastro manual", form.presence || lead.product.presence || "Sem detalhe"]
      else
        ["channel", channel_label(channel), form.presence || campaign.presence || "Sem detalhe"]
      end
    end

    def build_row(key, leads, context)
      type, title, detail = key
      lead_ids = leads.map(&:id)
      attended_count = leads.count { |lead| attended?(lead, context[:attended_at]) }
      contacted_count = leads.count { |lead| context[:attempts][lead.id].to_a.any? }
      opportunity_count = lead_ids.count { |id| opportunity?(id, context) }
      closed_count = lead_ids.count { |id| context[:closed_ids].include?(id) }

      {
        type: type,
        title: title,
        detail: detail,
        tone: row_tone(type),
        total: leads.size,
        attended_count: attended_count,
        contacted_count: contacted_count,
        opportunity_count: opportunity_count,
        closed_count: closed_count,
        conversion_rate: percentage(closed_count, leads.size),
        leads: leads.map { |lead| lead_row(lead, context) }
      }
    end

    def lead_row(lead, context)
      info = lead.other_information.to_h
      attribution = lead.attribution_data.to_h
      attempts = context[:attempts][lead.id].to_a
      attended = attended?(lead, context[:attended_at])
      site_event = context[:site_events][lead.id]
      contacted = attempts.any?
      has_opportunity = opportunity?(lead.id, context)
      closed = context[:closed_ids].include?(lead.id)

      {
        lead: lead,
        name: lead.name.presence || "Lead ##{lead.id}",
        source_label: lead_source_label(lead, context),
        campaign_label: campaign_name(info, attribution).presence || ad_name(info, attribution).presence || "sem campanha",
        broker_name: lead.admin_user&.name.presence || "Sem corretor",
        opened_label: opened_label(lead, context[:attended_at]),
        opened_tone: attended ? "green" : "red",
        contact_label: contact_label(attempts),
        contact_tone: contacted ? "amber" : "gray",
        result_label: result_label(attended: attended, contacted: contacted, opportunity: has_opportunity, closed: closed),
        result_tone: result_tone(attended: attended, contacted: contacted, opportunity: has_opportunity, closed: closed),
        property_label: property_label(lead, site_event),
        created_at: lead.created_at
      }
    end

    def campaign_name(info, attribution)
      info["meta_campaign_name"].presence ||
        info["campaign_name"].presence ||
        attribution["campaign_name"].presence ||
        attribution["utm_campaign"].presence ||
        whatsapp_referral(info)["headline"].presence
    end

    def ad_name(info, attribution)
      info["meta_ad_name"].presence ||
        attribution["ad_name"].presence ||
        attribution["utm_content"].presence ||
        whatsapp_referral(info)["body"].presence
    end

    def form_name(lead, info, attribution, context)
      context[:meta_form_names][lead.id].presence ||
        info["meta_form_name"].presence ||
        info["form_name"].presence ||
        lead.product.presence ||
        meta_form_reference(lead)["form_id"].presence ||
        attribution["form_id"].presence
    end

    def normalized_channel(lead)
      lead.attribution_channel.presence ||
        lead.attribution_source.presence ||
        lead.origin.presence ||
        "direct"
    end

    def meta_lead?(lead, info, attribution)
      lead.attribution_channel == "meta_ads" ||
        lead.origin.to_s.match?(/facebook|meta/i) ||
        info["meta_leadgen_id"].present? ||
        attribution["fbclid"].present? ||
        whatsapp_ad_referral?(info)
    end

    def whatsapp_ad_referral?(info)
      referral = whatsapp_referral(info)
      referral["source_type"] == "ad" && referral["source_id"].present?
    end

    def whatsapp_referral(info)
      entry = info["whatsapp_entry"]
      return {} unless entry.is_a?(Hash)

      referral = entry["referral"]
      referral.is_a?(Hash) ? referral : {}
    end

    def site_lead?(lead, channel, site_event)
      site_event.present? ||
        lead.origin.to_s.casecmp("site").zero? ||
        lead.lead_type.to_s.match?(/\A(?:site|whatsapp_modal|whatsapp_click)\z/i) ||
        lead.source_url.present?
    end

    def site_key(_lead, _channel, _site_event)
      ["site", "Site", "Conversões do site"]
    end

    def site_lead_detail(lead, channel, site_event)
      property = site_event&.habitation
      property = nil unless property&.tenant_id == @tenant.id
      page = site_page(site_event&.source_path.presence || lead.source_url)
      action = site_action_label(lead)
      channel_detail = site_channel_detail(channel)
      detail = if property
        "Imóvel ##{property.codigo}"
      elsif page.present?
        "Página #{page}"
      else
        "Origem do site"
      end
      detail = [channel_detail, detail, action].compact_blank.join(" · ")

      detail
    end

    def site_action_label(lead)
      case lead.lead_type.to_s
      when /whatsapp/i
        "Ação WhatsApp"
      when /phone|telefone/i
        "Ação telefone"
      when /form|site/i
        "Formulário do site"
      end
    end

    def site_channel_detail(channel)
      label = channel_label(channel)
      return if label.in?(["Site", "Direto / desconhecido"])

      label
    end

    def whatsapp_lead?(lead, channel)
      lead.origin.to_s.match?(/whatsapp/i) || channel.to_s.match?(/whatsapp|messaging/i)
    end

    def lead_source_label(lead, context)
      type, title, detail = campaign_key(lead, context)
      return [title, detail].compact_blank.join(" · ") if type == "meta"
      return ["Site", site_lead_detail(lead, normalized_channel(lead), context[:site_events][lead.id])].compact_blank.join(" · ") if type == "site"

      title
    end

    def property_label(lead, site_event)
      property = site_event&.habitation
      property = nil unless property&.tenant_id == @tenant.id
      return "Imóvel ##{property.codigo}" if property
      return "Imóvel ##{lead.property_id}" if lead.property_id.present?

      "Sem imóvel"
    end

    def channel_label(value)
      raw = value.to_s.strip
      normalized = raw.parameterize(separator: "_")
      return "Direto / desconhecido" if raw.blank? || normalized.in?(%w[direct unknown origem_nao_identificada direto_origem_desconhecida])
      return CHANNEL_LABELS[raw] if CHANNEL_LABELS.key?(raw)
      return "Meta Ads" if normalized.match?(/meta_ads|facebook_lead_ads/)
      return "WhatsApp" if normalized.include?("whatsapp")
      return "Site" if normalized.match?(/\Asite\z|formulario|whatsapp_modal|whatsapp_click/)
      return "Busca orgânica" if normalized == "organic_search"
      return "Social orgânico" if normalized == "organic_social"
      return "Cadastro manual" if normalized == "cadastro_manual"

      raw.tr("_-", " ").squish.titleize
    end

    def site_page(value)
      uri = URI.parse(value.to_s)
      return unless uri.scheme.nil? || %w[http https].include?(uri.scheme)

      uri.path.presence
    rescue URI::InvalidURIError
      nil
    end

    def attended?(lead, attended_at)
      attended_at[lead.id].present? || Lead.status_value(lead.status) == Lead.status_value(:em_atendimento)
    end

    def opened_label(lead, attended_at)
      return "abriu" if attended?(lead, attended_at)

      "não abriu"
    end

    def opportunity?(lead_id, context)
      context[:visit_ids].include?(lead_id) || context[:proposal_ids].include?(lead_id)
    end

    def contact_label(attempts)
      count = attempts.size
      return "sem tentativa" if count.zero?

      "#{count} #{'tentativa'.pluralize(count)}"
    end

    def result_label(attended:, contacted:, opportunity:, closed:)
      return "negócio fechado" if closed
      return "virou oportunidade" if opportunity
      return "contato registrado" if contacted
      return "atendido sem contato" if attended

      "aguardando atendimento"
    end

    def result_tone(attended:, contacted:, opportunity:, closed:)
      return "green" if closed
      return "blue" if opportunity
      return "amber" if contacted || attended

      "red"
    end

    def row_tone(type)
      {
        "meta" => "meta",
        "site" => "site",
        "whatsapp" => "whatsapp",
        "manual" => "manual",
        "unknown" => "gray"
      }.fetch(type, "channel")
    end

    def percentage(value, total)
      return 0 if total.to_i.zero?

      ((value.to_f / total.to_i) * 100).round(1)
    end
  end
end
