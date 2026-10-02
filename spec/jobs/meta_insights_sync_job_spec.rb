require "rails_helper"

RSpec.describe MetaInsightsSyncJob, type: :job do
  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }

  before do
    create(:user_meta_integration, admin_user: admin, tenant: tenant, access_token: "tok",
                                   ad_accounts: { "123" => "Conta" })
  end

  def insight_row(date, spend: "100.0", leads: 2)
    {
      "campaign_id" => "c1", "campaign_name" => "Campanha Porto Belo",
      "date_start" => date.iso8601, "spend" => spend,
      "impressions" => "1000", "clicks" => "50",
      "actions" => [{ "action_type" => "lead", "value" => leads.to_s },
                    { "action_type" => "link_click", "value" => "50" }]
    }
  end

  it "grava linhas diárias somando só ações de lead" do
    allow_any_instance_of(Facebook::MetaService).to receive(:campaign_insights)
      .and_return([insight_row(Date.current), insight_row(1.day.ago.to_date, spend: "50.0", leads: 1)])

    described_class.perform_now(tenant.id)

    rows = MetaCampaignInsight.for_tenant(tenant).ordered
    expect(rows.map(&:leads)).to eq([2, 1])
    expect(rows.map(&:spend).map(&:to_f)).to eq([100.0, 50.0])
    expect(rows.first.campaign_name).to eq("Campanha Porto Belo")
  end

  it "atualiza o dia existente (ajuste de atribuição) e ignora linha inválida" do
    MetaCampaignInsight.create!(tenant: tenant, campaign_id: "c1", campaign_name: "Camp",
                                date: Date.current, spend: 10, leads: 1)
    allow_any_instance_of(Facebook::MetaService).to receive(:campaign_insights)
      .and_return([insight_row(Date.current, spend: "120.0", leads: 3),
                   { "campaign_name" => "Sem id", "spend" => "9" }])

    described_class.perform_now(tenant.id)

    expect(MetaCampaignInsight.for_tenant(tenant).count).to eq(1)
    expect(MetaCampaignInsight.for_tenant(tenant).first).to have_attributes(spend: 120.0, leads: 3)
  end

  it "não faz nada sem integração e tolera erro por conta" do
    UserMetaIntegration.delete_all
    expect { described_class.perform_now(tenant.id) }.not_to raise_error
    expect(MetaCampaignInsight.for_tenant(tenant).count).to eq(0)

    create(:user_meta_integration, admin_user: admin, tenant: tenant, access_token: "tok",
                                   ad_accounts: { "123" => "Conta" })
    allow_any_instance_of(Facebook::MetaService).to receive(:campaign_insights)
      .and_raise(Koala::Facebook::APIError.new(400, nil, { "code" => 100 }))
    expect { described_class.perform_now(tenant.id) }.not_to raise_error
  end
end
