require "rails_helper"

RSpec.describe "Marketing events", type: :request do
  before do
    host! "localhost"
  end

  it "ignores passive tracking before LGPD consent" do
    expect {
      post marketing_events_path, params: {
        event_type: "footer_click",
        placement: "footer",
        label: "Contato",
        page_url: "http://localhost/"
      }
    }.not_to change(SeoConversionEvent, :count)

    expect(response).to have_http_status(:accepted)
  end

  it "records passive tracking after LGPD consent" do
    cookies[ApplicationController::LGPD_CONSENT_COOKIE] = "accepted"

    expect {
      post marketing_events_path, params: {
        event_type: "footer_click",
        placement: "footer",
        label: "Contato",
        page_url: "http://localhost/"
      }
    }.to change(SeoConversionEvent, :count).by(1)

    expect(response).to have_http_status(:accepted)
  end

  it "não vincula evento a imóvel de outro tenant" do
    other_tenant = Tenant.create!(name: "Outro marketing #{SecureRandom.hex(3)}", slug: "outro-marketing-#{SecureRandom.hex(3)}")
    habitation = create(:habitation, tenant: other_tenant)
    cookies[ApplicationController::LGPD_CONSENT_COOKIE] = "accepted"

    expect {
      post marketing_events_path, params: {
        event_type: "property_card_click",
        habitation_id: habitation.id,
        page_url: "http://localhost/imoveis"
      }
    }.to change(SeoConversionEvent, :count).by(1)

    expect(response).to have_http_status(:accepted)
    expect(SeoConversionEvent.order(:created_at).last.habitation_id).to be_nil
  end

  it "usa tenant_slug para vincular evento ao imóvel do tenant público solicitado" do
    tenant = Tenant.create!(name: "Tenant marketing #{SecureRandom.hex(3)}", slug: "tenant-marketing-#{SecureRandom.hex(3)}")
    habitation = create(:habitation, tenant: tenant)
    cookies[ApplicationController::LGPD_CONSENT_COOKIE] = "accepted"

    post marketing_events_path, params: {
      tenant_slug: tenant.slug,
      event_type: "property_card_click",
      habitation_id: habitation.id,
      page_url: "http://localhost/imoveis"
    }

    expect(response).to have_http_status(:accepted)
    expect(SeoConversionEvent.order(:created_at).last.habitation_id).to eq(habitation.id)
  end
end
