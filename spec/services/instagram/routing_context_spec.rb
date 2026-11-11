require "rails_helper"

RSpec.describe Instagram::RoutingContext do
  let(:integration) { create(:user_meta_integration) }
  let(:tenant) { integration.tenant }
  let!(:page) { create(:meta_facebook_page, user_meta_integration: integration, instagram_id: "12345", instagram_enabled: true) }
  let(:lead) { create(:lead, tenant: tenant, instagram_account_id: "12345", instagram_scoped_id: "98765",
    other_information: {"instagram_capture" => {"step" => "serving"}}) }
  before { integration.update!(selected_page_ids: [page.page_id]) }

  it "reconstrói página e intenção de um Direct antigo somente com mensagens do cliente" do
    lead.instagram_messages.create!(message_id: "intent", body: "Comprar", occurred_at: Time.current)
    lead.instagram_messages.create!(message_id: "bot", body: "Alugar", direction: "outbound", occurred_at: Time.current)
    described_class.apply(lead)
    expect(lead.other_information).to include("meta_page_id" => page.page_id, "business_type" => "venda")
    expect(lead.other_information.dig("instagram_capture", "business_type_message_id")).to eq(lead.instagram_messages.inbound.sole.id)
    expect(lead.reload.other_information["business_type"]).to be_nil
  end

  it "não inventa modalidade a partir de sugestão da IA ou nome de campanha" do
    lead.instagram_messages.create!(message_id: "bot", body: "Você quer comprar ou alugar?", direction: "outbound", occurred_at: Time.current)
    lead.other_information["meta_campaign_name"] = "Venda Refuge"
    described_class.apply(lead)
    expect(lead.other_information["business_type"]).to be_nil
  end

  it "preserva modalidade explícita e atribuição de campanha" do
    lead.other_information.merge!("business_type" => "locacao", "meta_campaign_id" => "campaign")
    lead.instagram_messages.create!(message_id: "intent", body: "Comprar", occurred_at: Time.current)
    described_class.apply(lead)
    expect(lead.other_information).to include("business_type" => "locacao", "meta_campaign_id" => "campaign")
  end

  it "não usa página de outra conta nem página desmarcada" do
    other = Tenant.create!(name: "Outra", slug: "instagram-context-other")
    lead.tenant = other
    described_class.apply(lead)
    expect(lead.other_information["meta_page_id"]).to be_nil
    lead.tenant = tenant
    integration.update!(selected_page_ids: [])
    described_class.apply(lead)
    expect(lead.other_information["meta_page_id"]).to be_nil
  end
end
