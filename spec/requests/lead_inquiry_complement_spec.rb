require "rails_helper"

RSpec.describe "Lead inquiry complement", type: :request do
  let(:lead_mailer) { double("LeadMailer parametrizado") }
  let(:welcome_delivery) { double("Boas-vindas", deliver_later: nil) }

  before do
    host! "localhost"
    allow(WebhookService).to receive(:send_form_data)
    allow(LeadMailer).to receive(:with).and_return(lead_mailer)
    allow(lead_mailer).to receive(:welcome_lead).and_return(welcome_delivery)
    allow(Leads::NotificationDispatcher).to receive(:notify_complement)
  end

  def distributed_lead(tenant, broker, rule, phone:)
    lead = create(:lead, tenant: tenant, phone: phone, admin_user: broker, distribution_rule: rule, status: "Aguardando Aceite")
    lead.activities.create!(kind: "distributed", metadata: { "admin_user_id" => broker.id })
    lead
  end

  it "agrega a segunda consulta do site ao lead aberto em vez de duplicar corretor" do
    tenant = Tenant.default
    broker = create(:admin_user, tenant: tenant, profile: tenant.profiles.find_by!(key: "agent"), active: true)
    rule = create(:distribution_rule, tenant: tenant, require_active_checkin: false, pocket_active: true, pocket_time: 20)
    first = distributed_lead(tenant, broker, rule, phone: "554799991111")
    second_property = create(:habitation, tenant: tenant)

    expect do
      post leads_path, params: {
        lead: { name: "Marilene", phone: "4799991111", lead_type: "whatsapp_modal",
                origin: "Site", property_id: second_property.id, page_url: "http://localhost/imovel-b" }
      }, as: :json
    end.not_to change(Lead, :count)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["success"]).to be(true)
    expect(first.reload.property_interests.map(&:habitation_id)).to include(second_property.id)
    expect(first.activities.where(kind: "inquiry_complemented").count).to eq(1)
    expect(welcome_delivery).not_to have_received(:deliver_later)
    expect(WebhookService).to have_received(:send_form_data).with(
      "whatsapp_lead", hash_including(complemented_inquiry: true), anything
    )
    expect(Leads::NotificationDispatcher).to have_received(:notify_complement)
  end

  it "cria lead novo quando o anterior saiu da janela do pocket" do
    tenant = Tenant.default
    broker = create(:admin_user, tenant: tenant, profile: tenant.profiles.find_by!(key: "agent"), active: true)
    rule = create(:distribution_rule, tenant: tenant, require_active_checkin: false, pocket_active: true, pocket_time: 20)
    first = distributed_lead(tenant, broker, rule, phone: "554799992222")
    first.activities.where(kind: "distributed").update_all(created_at: 2.hours.ago)
    first.update_columns(created_at: 2.hours.ago)
    second_property = create(:habitation, tenant: tenant)

    expect do
      post leads_path, params: {
        lead: { name: "Marilene", phone: "4799992222", lead_type: "whatsapp_modal",
                origin: "Site", property_id: second_property.id, page_url: "http://localhost/imovel-b" }
      }, as: :json
    end.to change(Lead, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(first.reload.property_interests).to be_empty
  end
end
