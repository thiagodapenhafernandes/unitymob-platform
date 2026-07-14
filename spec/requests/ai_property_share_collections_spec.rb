require "rails_helper"

RSpec.describe "AI property share collections", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:broker) { create(:admin_user, :field_agent) }
  let(:first_property) { create(:habitation, tenant: broker.tenant, codigo: "SHARED-A") }
  let(:second_property) { create(:habitation, tenant: broker.tenant, codigo: "SHARED-B") }
  let(:mobile_headers) { { "User-Agent" => "Mozilla/5.0 (iPhone) Mobile", "Accept" => "application/json" } }

  before do
    host! "localhost"
    broker.profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    PropertySetting.instance(tenant: broker.tenant).update!(ai_property_search_enabled: true)
  end

  it "cria seleção tenant-scoped e registra auditoria" do
    sign_in broker
    post field_property_share_collections_path, params: { habitation_ids: [first_property.id, second_property.id] }, headers: mobile_headers

    collection = AiPropertyShareCollection.last
    expect(response).to have_http_status(:ok)
    expect(collection).to have_attributes(tenant_id: broker.tenant_id, admin_user_id: broker.id)
    expect(collection.habitations).to contain_exactly(first_property, second_property)
    expect(collection.audit_events.pluck(:event_type)).to include("collection_created")
  end

  it "aplica as opções operacionais salvas no PropertySetting" do
    setting = PropertySetting.instance(tenant: broker.tenant)
    setting.update!(
      ai_property_search_share_max_properties: 1,
      ai_property_search_share_expiration_days: 7,
      ai_property_search_share_title: "Curadoria personalizada",
      ai_property_search_share_message: "%{count} opção para você",
      ai_property_search_public_eyebrow: "Escolhas do corretor",
      ai_property_search_interest_button_label: "Quero conversar"
    )
    sign_in broker

    post field_property_share_collections_path, params: { habitation_ids: [first_property.id, second_property.id] }, headers: mobile_headers

    collection = AiPropertyShareCollection.last
    expect(collection.habitations.size).to eq(1)
    expect(collection.expires_at).to be_within(5.seconds).of(7.days.from_now)
    expect(response.parsed_body).to include("share_title" => "Curadoria personalizada", "share_message" => "1 opção para você")

    get ai_property_share_collection_path(collection.token)
    expect(response.body).to include("Escolhas do corretor", "Quero conversar")
  end

  it "pede identificação uma vez, cria lead e agrupa interesses posteriores" do
    collection = create_collection

    post_interest(collection, habitation_id: first_property.id)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["requires_identity"]).to be(true)

    post_interest(collection, habitation_id: first_property.id, name: "Maria", phone: "(47) 99999-0000")
    lead = broker.tenant.leads.order(:created_at).last
    expect(lead).to have_attributes(admin_user_id: broker.id, origin: "Seleção compartilhada")

    post_interest(collection, habitation_id: second_property.id)
    expect(response).to have_http_status(:ok)
    expect(lead.reload.interest_properties).to contain_exactly(first_property, second_property)
    expect(collection.audit_events.pluck(:event_type)).to include("lead_created_from_interest", "interest_created")
  end

  it "não transfere lead existente de outro corretor" do
    owner = create(:admin_user, tenant: broker.tenant)
    existing = create(:lead, tenant: broker.tenant, admin_user: owner, name: "Cliente existente", phone: "47999990000")
    collection = create_collection

    post_interest(collection, habitation_id: first_property.id, name: "Cliente existente", phone: "47999990000")

    expect(existing.reload.admin_user).to eq(owner)
    expect(existing.interest_properties).to include(first_property)
    event = collection.audit_events.find_by!(event_type: "visitor_matched_existing_lead")
    expect(event.admin_user).to eq(owner)
    expect(event.metadata["shared_by_admin_user_id"]).to eq(broker.id)
  end

  private

  def create_collection
    broker.tenant.ai_property_share_collections.create!(admin_user: broker).tap do |collection|
      collection.items.create!(habitation: first_property)
      collection.items.create!(habitation: second_property)
    end
  end

  def post_interest(collection, **params)
    get ai_property_share_collection_path(collection.token)
    csrf = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')&.fetch("content")
    post interest_ai_property_share_collection_path(collection.token), params:, headers: { "X-CSRF-Token" => csrf, "Accept" => "application/json" }
  end
end
