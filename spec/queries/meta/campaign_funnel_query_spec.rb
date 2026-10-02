require "rails_helper"

RSpec.describe Meta::CampaignFunnelQuery do
  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }

  def meta_lead(campaign_id, **attrs)
    create(:lead, tenant: tenant, attribution_channel: "meta_ads", admin_user: admin,
                  other_information: { "meta_campaign_id" => campaign_id,
                                       "meta_campaign_name" => "Camp #{campaign_id}" }.merge(attrs.delete(:info) || {}),
                  **attrs)
  end

  it "agrupa por campanha e conta marcos do funil" do
    Current.set(tenant: tenant) do
      pipeline = LeadPipeline.ensure_default!(tenant: tenant)
      open_stage = create(:lead_pipeline_stage, lead_pipeline: pipeline, tenant: tenant,
                                                name: "Aberta Q", stage_type: "open")
      won = create(:lead_pipeline_stage, lead_pipeline: pipeline, tenant: tenant,
                                         name: "Ganha Q", stage_type: "won")
      l1 = meta_lead("c1", broker_qualification_status: "qualified")
      l2 = meta_lead("c1")
      l3 = meta_lead("c2")
      # No create o status vence a etapa explícita (sync_pipeline_stage).
      l1.update_columns(lead_pipeline_stage_id: open_stage.id)
      l2.update_columns(lead_pipeline_stage_id: won.id)
      l3.update_columns(lead_pipeline_stage_id: open_stage.id)
      create(:appointment, tenant: tenant, lead: l1, admin_user: admin,
                           kind: "visita", status: "realizado")
      create(:lead, tenant: tenant, origin: "site", admin_user: admin)

      rows = described_class.new(tenant: tenant, starts_at: 30.days.ago, ends_at: Time.current).call.rows

      c1 = rows.find { |row| row[:campaign_id] == "c1" }
      expect(c1).to include(leads: 2, qualified: 1, visits: 1, sales: 1)
      expect(c1[:campaign_name]).to eq("Camp c1")
      expect(rows.find { |row| row[:campaign_id] == "c2" }).to include(leads: 1, qualified: 0)
      expect(rows.map { |row| row[:campaign_id] }).not_to include(nil)
    end
  end

  it "prefere o nome do snapshot e retorna vazio sem leads" do
    Current.set(tenant: tenant) do
      meta_lead("c9")
      MetaCampaignInsight.create!(tenant: tenant, campaign_id: "c9", campaign_name: "Snapshot Nome",
                                  date: Date.current)

      rows = described_class.new(tenant: tenant, starts_at: 30.days.ago, ends_at: Time.current).call.rows
      expect(rows.first[:campaign_name]).to eq("Snapshot Nome")

      empty = described_class.new(tenant: tenant, starts_at: 60.days.ago, ends_at: 31.days.ago).call.rows
      expect(empty).to eq([])
    end
  end
end
