require "rails_helper"

RSpec.describe "Distribuição LinkedIn" do
  let(:integration) { create(:linkedin_integration) }
  let(:rule) { create(:distribution_rule, tenant: integration.tenant, source_site: false, source_linkedin: true, linkedin_campaign_ids: ["456"], linkedin_form_ids: ["789"]) }
  let(:lead) do
    build(:lead, tenant: integration.tenant, origin: "LinkedIn Ads", attribution_channel: "linkedin_ads", attribution_source: "linkedin",
      other_information: { "linkedin_account_id" => "123", "linkedin_campaign_id" => "456", "linkedin_form_id" => "789" })
  end
  let(:distributor) { Leads::DistributorService.new(lead) }

  it "encontra a regra da campanha e do formulário" do
    rule
    expect(distributor.send(:find_matching_rule)).to eq(rule)
  end

  it "não distribui uma campanha diferente mesmo quando compartilha o formulário" do
    rule
    lead.other_information["linkedin_campaign_id"] = "457"
    expect(distributor.send(:find_matching_rule)).to be_nil
  end

  it "não aceita formulário de outra campanha por submissão direta" do
    rule.linkedin_form_ids = ["external"]
    expect(rule).not_to be_valid
    expect(rule.errors[:linkedin_form_ids]).to be_present
  end

  it "com filtros vazios aceita novos formulários das contas conectadas" do
    rule.update!(linkedin_campaign_ids: [], linkedin_form_ids: [])
    lead.other_information.merge!("linkedin_campaign_id" => "457", "linkedin_form_id" => "790")
    expect(distributor.send(:find_matching_rule)).to eq(rule)
  end

  it "interrompe o roteamento ao desmarcar a conta na integração" do
    rule
    integration.update!(selected_account_ids: [])
    expect(distributor.send(:find_matching_rule)).to be_nil
  end

  it "não encontra regras pertencentes a outro tenant" do
    rule
    lead.tenant = Tenant.create!(name: "Outro tenant", slug: "linkedin-routing-other")
    expect(distributor.send(:find_matching_rule)).to be_nil
  end

  it "não deixa uma regra exclusiva Meta capturar um lead LinkedIn" do
    create(:distribution_rule, tenant: integration.tenant, source_site: false, source_meta: true)
    expect(distributor.send(:find_matching_rule)).to be_nil
  end
end
