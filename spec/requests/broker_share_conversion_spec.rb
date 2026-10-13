require "rails_helper"

RSpec.describe "Conversão pelo link do corretor", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:tenant) { Tenant.default }
  let(:broker) { create(:admin_user, tenant: tenant, active: true) }
  let(:property) { create(:habitation, tenant: tenant) }
  let(:share) { HabitationShareLink.for_broker_page(broker: broker, habitations: [property]).fetch(property.id) }
  let(:phone) { "47999998765" }

  before do
    host! "localhost"
    allow(WebhookService).to receive(:send_form_data)
    allow(LeadMailer).to receive_message_chain(:with, :welcome_lead, :deliver_later)
    allow(Leads::NotificationDispatcher).to receive(:notify_direct_assignment)
    allow(Leads::NotificationDispatcher).to receive(:notify_complement)
    integration = instance_double(WhatsappBusinessIntegration, whatsapp_url_for: "https://wa.me/5547999999999",
      site_phone_settings: {}, messaging_ready?: false, redirect_after_capture_for?: false)
    allow(WhatsappBusinessIntegration).to receive(:current).and_return(integration)
    LeadSetting.instance(tenant: tenant).update!(stickiness_match: "phone")
  end

  def convert(token = share.token, property_id: property.id)
    post leads_path, params: { lead: { name: "Cliente", phone: phone, property_id: property_id,
      share_token: token, lead_type: "whatsapp_click", origin: "Compartilhamento Corretor" } }, as: :json
    expect(response).to have_http_status(:ok), response.body
  end

  it "atribui um novo contato diretamente ao corretor sem rodízio" do
    expect(Leads::DistributorService).not_to receive(:find_and_distribute)
    convert
    lead = tenant.leads.find_by!(phone: "5547999998765")
    expect(lead.admin_user_id).to eq(broker.id)
    expect(lead.shared_by_admin_user_id).to eq(broker.id)
    expect(lead.activities.where(kind: "assigned_directly")).to be_present
  end

  it "reutiliza contato em atendimento com outro corretor e atribui ao dono do link" do
    other = create(:admin_user, tenant: tenant)
    original = create(:lead, tenant: tenant, phone: phone, admin_user: other, status: "Em Atendimento")
    expect(Leads::DistributorService).not_to receive(:redistribute)
    expect(Leads::NotificationDispatcher).to receive(:notify_direct_assignment)
      .with(have_attributes(id: original.id, admin_user_id: broker.id)).once
    expect { convert }.not_to change(tenant.leads, :count)
    expect(original.reload).to have_attributes(admin_user_id: broker.id, shared_by_admin_user_id: broker.id,
      share_token: share.token, distribution_rule_id: nil)
    expect(original.property_interests.pluck(:habitation_id)).to include(property.id)
    expect(original.activities.find_by!(kind: "inquiry_complemented").metadata.dig("previous_assignment", "admin_user_id")).to eq(other.id)
  end

  it "retira contato represado ou arquivado da fila e atribui diretamente" do
    original = create(:lead, tenant: tenant, phone: phone, status: "Descartado")
    original.update_columns(archived_at: 1.day.ago, contingency_pending: true)
    convert
    expect(original.reload).to have_attributes(admin_user_id: broker.id, archived_at: nil, contingency_pending: false)
  end

  it "não usa o vínculo automático para usuário logado" do
    sign_in broker
    expect(Leads::DistributorService).to receive(:find_and_distribute)
    convert
    expect(tenant.leads.find_by!(phone: "5547999998765").admin_user_id).to be_nil
  end

  it "não leva o vínculo por cookie para uma conversão no site normal" do
    cookies[ApplicationController::LGPD_CONSENT_COOKIE] = "accepted"
    get habitation_path(property, share_token: share.token)
    expect(response.cookies[HabitationShareLink::COOKIE_KEY.to_s]).to be_nil
    get habitation_path(property)
    expect(Nokogiri::HTML(response.body).at_css(".public-habitations-show__broker-card")).to be_nil
    expect(Leads::DistributorService).to receive(:find_and_distribute)
    post leads_path, params: { lead: { name: "Cliente Site", phone: phone, property_id: property.id } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(tenant.leads.find_by!(phone: "5547999998765").admin_user_id).to be_nil
  end

  it "não aplica a nova precedência a compartilhamentos manuais existentes" do
    other = create(:admin_user, tenant: tenant)
    original = create(:lead, tenant: tenant, phone: phone, admin_user: other, status: "Em Atendimento")
    manual = HabitationShareLink.create_or_reuse_for(habitation: property, admin_user: broker)
    expect(manual).not_to be_broker_page
    expect(Leads::DistributorService).to receive(:redistribute).and_return(:kept)
    convert(manual.token)
    expect(original.reload.admin_user_id).to eq(other.id)
  end

  it "não usa token de outro imóvel, de outra conta, expirado ou corretor inativo" do
    other_property = create(:habitation, tenant: tenant)
    other_tenant = Tenant.create!(name: "Outra", slug: "share-other-#{SecureRandom.hex(3)}")
    other_share = HabitationShareLink.create!(habitation: create(:habitation, tenant: other_tenant), admin_user: create(:admin_user, tenant: other_tenant))
    allow(Leads::DistributorService).to receive(:find_and_distribute)
    convert(share.token, property_id: other_property.id)
    expect(tenant.leads.find_by!(phone: "5547999998765").shared_by_admin_user_id).to be_nil
    convert(other_share.token)
    share.update!(expires_at: 1.minute.ago)
    convert
    share.update!(expires_at: 1.day.from_now)
    broker.update!(active: false)
    convert
    expect(tenant.leads.find_by!(phone: "5547999998765").shared_by_admin_user_id).to be_nil
  end
end
