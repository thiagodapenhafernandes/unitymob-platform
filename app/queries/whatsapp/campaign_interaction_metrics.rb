module Whatsapp
  class CampaignInteractionMetrics
    def initialize(tenant:, campaigns:)
      @campaigns = campaigns.where(tenant_id: tenant.id).except(:includes, :preload, :eager_load, :order, :limit, :offset)
      @events = tenant.whatsapp_campaign_interactions.where(whatsapp_campaign_id: @campaigns.select(:id))
    end

    def by_campaign
      @by_campaign ||= begin
        rows = Hash.new { |hash, key| hash[key] = {interactions: 0, clicks: 0, free_responses: 0, outcomes: {}} }
        responses.group(:whatsapp_campaign_id).distinct.count(:recipient_key).each { |id, n| rows[id][:interactions] = n }
        responses.where.not(button_text: [nil, ""]).group(:whatsapp_campaign_id).count.each { |id, n| rows[id][:clicks] = n }
        responses.where(button_text: [nil, ""]).group(:whatsapp_campaign_id).distinct.count(:recipient_key).each { |id, n| rows[id][:free_responses] = n }
        @events.actions.group(:whatsapp_campaign_id, :outcome).distinct.count(:recipient_key).each do |(id, outcome), n|
          rows[id][:outcomes][outcome] = n if outcome.present?
        end
        rows
      end
    end

    def totals
      result = {interactions: 0, clicks: 0, free_responses: 0, outcomes: {}}
      by_campaign.each_value do |row|
        %i[interactions clicks free_responses].each { |key| result[key] += row[key] }
        row[:outcomes].each { |key, n| result[:outcomes][key] = result[:outcomes].fetch(key, 0) + n }
      end
      responses
      result.merge(history_incomplete: @legacy_messages.exists? || @events.responses.where("metadata ->> 'legacy_snapshot' = ?", "true").exists?)
    end

    def button_cards(campaign)
      definitions = campaign.response_decision_rows.index_by { |button| button["key"] }
      pairs = responses.where(whatsapp_campaign_id: campaign.id).where.not(button_text: [nil, ""]).distinct.pluck(:button_key, :button_text)
      by_text = definitions.values.group_by { |button| button["text"].to_s.downcase }
        .select { |_text, buttons| buttons.one? }.transform_values(&:first)
      pairs.each do |key, text|
        key ||= by_text[text.to_s.downcase]&.dig("key") || "historical-text:#{text.to_s.downcase}"
        definitions[key] ||= {"key" => key, "text" => text, "action_label" => "Botão do histórico", "kind" => "quick_reply", "historical" => true}
      end
      connection = WhatsappCampaignInteraction.connection
      clauses = by_text.map { |text, button| "WHEN LOWER(button_text) = #{connection.quote(text)} THEN #{connection.quote(button['key'])}" }.join(" ")
      legacy_key = clauses.present? ? "CASE #{clauses} ELSE 'historical-text:' || LOWER(button_text) END" : "'historical-text:' || LOWER(button_text)"
      expression = Arel.sql("COALESCE(button_key, #{legacy_key})")
      counts = responses.where(whatsapp_campaign_id: campaign.id).where.not(button_text: [nil, ""]).group(expression).distinct.count(:recipient_key)
      clicks = responses.where(whatsapp_campaign_id: campaign.id).where.not(button_text: [nil, ""]).group(expression).count
      definitions.values.map do |button|
        trackable = button["kind"].to_s == "quick_reply" || clicks.fetch(button["key"], 0).positive?
        n = counts.fetch(button["key"], 0)
        {key: button["key"], label: button["text"], context: button["context"], action: button["action"],
         action_label: button["historical"] ? "Botão preservado do histórico" : "Ação atual: #{button['action_label']}", count: trackable ? n : nil,
         clicks: clicks.fetch(button["key"], 0), rate: trackable ? rate(n, campaign.delivered_count) : nil,
         tone: campaign.send(:response_action_tone, button["action"]), icon: campaign.send(:response_action_icon, button["action"]),
         hint: trackable ? "#{clicks.fetch(button['key'], 0)} cliques recebidos · pessoas únicas por botão" : "A Meta não informa cliques deste tipo por mensagem"}
      end
    end

    private

    def responses
      @responses ||= begin
        columns = "whatsapp_campaign_id, recipient_key, button_key, button_text, occurred_at"
        recorded = @events.responses.select(Arel.sql(columns)).to_sql
        @legacy_messages = WhatsappCampaignMessage.where(whatsapp_campaign_id: @campaigns.select(:id), status: "replied")
          .where.not(id: @events.responses.select(:whatsapp_campaign_message_id))
        legacy = @legacy_messages.select(Arel.sql("whatsapp_campaign_id, encode(sha256(convert_to(regexp_replace(phone_number, '[^0-9]', '', 'g'), 'UTF8')), 'hex') AS recipient_key, NULL::varchar AS button_key, reply_button_text AS button_text, replied_at AS occurred_at")).to_sql
        WhatsappCampaignInteraction.from("(#{recorded} UNION ALL #{legacy}) AS whatsapp_campaign_interactions")
      end
    end

    def rate(n, base)
      base.to_i.positive? ? (100.0 * n / base).round(1) : 0
    end
  end
end
