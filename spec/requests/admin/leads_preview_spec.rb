require "rails_helper"

RSpec.describe "Admin leads preview", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "preview-#{SecureRandom.hex(8)}@salute.test") }
  let(:tenant) { admin.tenant }
  let(:lead) do
    create(:lead, tenant: tenant, admin_user: admin, name: "Preview Lead",
                  phone: "5547999998888", email: "preview@lead.test")
  end

  before do
    host! "localhost"
    sign_in admin
  end

  it "renders the operational summary inside the preview frame" do
    LeadActivity.log!(lead: lead, kind: "note",
                      metadata: { contact_kind: "whatsapp", contact_result: "falou_com_cliente", body: "Mostrou interesse", by: admin.name })

    get preview_admin_lead_path(lead)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="lead_preview_frame"')
    expect(response.body).to include("Preview Lead", "5547999998888", "preview@lead.test")
    expect(response.body).to include("Corretor: #{admin.name}")
    expect(response.body).to include("WhatsApp", "Falou com cliente", "Mostrou interesse")
    expect(response.body).to include("Abrir lead", admin_lead_path(lead))
  end

  it "renders muted fallbacks without property or activities" do
    lead.activities.delete_all

    get preview_admin_lead_path(lead)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Contato geral")
    expect(response.body).to include("Nenhuma atividade registrada.")
  end

  it "returns not found for another tenant lead" do
    other_tenant = Tenant.create!(name: "Outro preview #{SecureRandom.hex(3)}", slug: "outro-preview-#{SecureRandom.hex(3)}")
    other_lead = create(:lead, tenant: other_tenant)

    get preview_admin_lead_path(other_lead)

    expect(response).to have_http_status(:not_found)
  end

  it "requires login" do
    sign_out admin

    get preview_admin_lead_path(lead)

    expect(response).to have_http_status(:found)
  end
end
