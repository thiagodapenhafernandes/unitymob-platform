# Sincroniza insights Meta (investimento/entrega/leads por campanha e dia)
# para um tenant. Janela móvel de 30 dias com upsert: idempotente e corrige
# ajustes retroativos de atribuição da Meta. Falha por conta não impede as
# demais; token expirado apenas pausa (volta no próximo ciclo após reconexão).
class MetaInsightsSyncJob < ApplicationJob
  queue_as :sync

  WINDOW_DAYS = 30

  retry_on Faraday::Error, Timeout::Error, SocketError, wait: :polynomially_longer, attempts: 3

  def perform(tenant_id)
    tenant = Tenant.find_by(id: tenant_id)
    return unless tenant

    Current.set(tenant: tenant) do
      UserMetaIntegration.owned_by_tenant(tenant.id).where.not(access_token: [nil, ""]).find_each do |integration|
        sync_integration(tenant, integration)
      end
    end
  end

  private

  def sync_integration(tenant, integration)
    service = Facebook::MetaService.new(integration.access_token)
    integration.ad_account_ids.each do |account_id|
      rows = service.campaign_insights(account_id, start_date: WINDOW_DAYS.days.ago.to_date, end_date: Date.current)
      upsert_rows(tenant, account_id, rows)
    rescue Koala::Facebook::APIError => e
      Rails.logger.warn "[MetaInsightsSyncJob] tenant=#{tenant.id} act=#{account_id} meta_error=#{e.fb_error_code}"
    end
  rescue StandardError => e
    Rails.logger.warn "[MetaInsightsSyncJob] tenant=#{tenant.id} integration=#{integration.id} error=#{e.class}: #{e.message.to_s.truncate(300)}"
  end

  def upsert_rows(tenant, account_id, rows)
    records = rows.filter_map do |row|
      campaign_id = row["campaign_id"].to_s
      date = parse_date(row["date_start"] || row["date_stop"])
      next if campaign_id.blank? || date.nil?

      {
        tenant_id: tenant.id,
        ad_account_id: account_id.to_s,
        campaign_id: campaign_id,
        campaign_name: row["campaign_name"].to_s,
        date: date,
        spend: row["spend"].to_f,
        impressions: row["impressions"].to_i,
        clicks: row["clicks"].to_i,
        leads: Facebook::MetaService.lead_count_from_actions(row["actions"]),
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    return if records.empty?

    MetaCampaignInsight.upsert_all(
      records,
      unique_by: :index_meta_campaign_insights_unique_row,
      update_only: [:ad_account_id, :campaign_name, :spend, :impressions, :clicks, :leads]
    )
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
