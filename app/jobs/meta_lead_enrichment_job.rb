# Reads only: enrichment never changes ownership, status or distribution.
class MetaLeadEnrichmentJob < ApplicationJob
  queue_as :sync
  retry_on Koala::Facebook::APIError, wait: :polynomially_longer, attempts: 3

  def perform(tenant_id, lead_id)
    tenant = Tenant.find_by(id: tenant_id)
    lead = tenant&.leads&.find_by(id: lead_id)
    return unless lead
    info = lead.other_information.to_h
    return if info["meta_enriched_at"].present?
    return unless lead.attribution_channel == "meta_ads" || info["meta_leadgen_id"].present?

    integrations = UserMetaIntegration.where(tenant_id: tenant.id)
      .where.not(ad_account_id: [nil, ""]).select do |candidate|
        !candidate.expired? && candidate.access_token.present? &&
          (info["meta_integration_user_id"].blank? || candidate.admin_user_id.to_s == info["meta_integration_user_id"].to_s)
      end
    return unless integrations.one?
    integration = integrations.first

    tracking = lead.attribution_data.to_h
    # No guessing from utm_campaign/fbclid: these are not Graph object IDs.
    ad_id = graph_id(info["ad_id"] || tracking["ad_id"])
    campaign_id = graph_id(info["campaign_id"] || tracking["campaign_id"])
    form = integration.meta_lead_forms.find_by(form_id: info["meta_form_id"].to_s) if info["meta_form_id"].present?
    if ad_id.nil? && form && graph_id(info["meta_leadgen_id"])
      page = form.meta_facebook_page
      details = Koala::Facebook::API.new(page.access_token).get_object(info["meta_leadgen_id"], fields: "id,ad_id,form_id")
      return unless details["form_id"].to_s == form.form_id
      ad_id = graph_id(details["ad_id"])
    end
    return unless ad_id || campaign_id || form

    service = Facebook::MetaService.new(integration.access_token)
    data = {}
    if ad_id
      ad = service.ad_details(ad_id)
      return unless ad["account_id"].to_s == integration.ad_account_id && ad["id"].to_s == ad_id
      data.merge!("meta_ad_id" => ad_id, "meta_ad_name" => ad["name"],
        "meta_campaign_id" => ad.dig("campaign", "id"), "meta_campaign_name" => ad.dig("campaign", "name"),
        "meta_adset_id" => ad.dig("adset", "id"), "meta_adset_name" => ad.dig("adset", "name"))
    elsif campaign_id
      campaign = service.campaign_details(campaign_id)
      return unless campaign["account_id"].to_s == integration.ad_account_id && campaign["id"].to_s == campaign_id
      data.merge!("meta_campaign_id" => campaign_id, "meta_campaign_name" => campaign["name"])
    end
    data["meta_form_name"] = form.name if form
    lead.with_lock do
      # Merge only enrichment keys so another operation cannot lose its data.
      lead.update_columns(other_information: lead.other_information.to_h.merge(data.compact).merge(
        "meta_enriched_at" => Time.current.iso8601, "meta_ad_account_id" => integration.ad_account_id))
    end
  end

  private

  def graph_id(value)
    value.to_s if value.to_s.match?(/\A[0-9]{5,30}\z/)
  end
end
