require "rails_helper"

RSpec.describe Tiktok::ReceiveLead do
  let(:admin) { create(:admin_user, :admin) }
  let(:integration) { TiktokIntegration.create!(tenant: admin.tenant, admin_user: admin, access_token: "private-token", selected_account_ids: ["123"]) }
  let(:entry) { { "id" => "lead-1", "advertiser_id" => "123", "page_id" => "456", "page_name" => "Apartamento", "campaign_id" => "789", "campaign_name" => "Lançamento", "changes" => [{ "field" => "name", "value" => "Cliente" }, { "field" => "email", "value" => "cliente@example.com" }] } }

  it "creates an attributed email-only lead once and preserves answers" do
    described_class.call(integration, entry)
    expect { described_class.call(integration, entry) }.not_to change(Lead, :count)
    lead = TiktokLeadReceipt.find_by!(tenant: admin.tenant, external_id: "lead-1").lead
    expect(lead.tenant).to eq(admin.tenant)
    expect(lead.attribution_channel).to eq("tiktok_ads")
    expect(lead.attribution_data["campaign_name"]).to eq("Lançamento")
    expect(lead.other_information["tiktok_answers"]["email"]).to eq("cliente@example.com")
    expect(integration.reload.last_lead_received_at).to be_present
    expect(integration.access_token_before_type_cast).not_to include("private-token")
  end

  it "routes through the existing Shark Tank rule with advertiser/form filters" do
    integration.update!(catalog: { "123" => { "name" => "Conta", "forms" => [{ "id" => "456", "name" => "Apartamento" }] } })
    rule = create(:distribution_rule, tenant: admin.tenant, source_site: false, source_tiktok: true, tiktok_account_ids: ["123"], tiktok_form_ids: ["456"], distribution_mode: :shark_tank)
    TiktokLeadProcessingJob.perform_now(integration.id, entry)
    lead = TiktokLeadReceipt.find_by!(tenant: admin.tenant, external_id: "lead-1").lead
    expect(lead.distribution_rule_id).to eq(rule.id)
    expect(lead.activities.where(kind: "shark_tank_ready")).to exist
  end

  it "rejects advertisers outside the selected tenant connection" do
    expect { described_class.call(integration, entry.merge("advertiser_id" => "999")) }.to raise_error(Tiktok::Client::Error)
    expect(TiktokLeadReceipt.count).to eq(0)
  end

  it "keeps no receipt when the form has no valid contact" do
    entry["changes"] = [{ "field" => "email", "value" => "invalid" }]
    expect { described_class.call(integration, entry) }.to raise_error(Tiktok::Client::Error)
    expect(TiktokLeadReceipt.count).to eq(0)
  end

  it "does not route TikTok leads through a site-only rule" do
    lead = build(:lead, tenant: admin.tenant, origin: "TikTok Ads", attribution_channel: "tiktok_ads", attribution_source: "tiktok")
    distributor = Leads::DistributorService.new(lead)
    rule = build(:distribution_rule, tenant: admin.tenant, source_site: true, source_tiktok: false)
    expect(distributor.send(:matches_source?, rule)).to eq(false)
    rule.source_tiktok = true
    expect(distributor.send(:matches_source?, rule)).to eq(true)
  end
end
