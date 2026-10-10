require "rails_helper"

RSpec.describe "Admin::Leads reconcile_inquiry", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "reconcile-#{SecureRandom.hex(8)}@salute.test") }
  let(:target) { create(:lead, tenant: admin.tenant, admin_user: admin) }
  let(:inquiry) do
    create(:lead, tenant: admin.tenant, admin_user: admin,
      other_information: { "unverified_inquiry" => true, "share_collection_id" => 1 })
  end

  before do
    host! "localhost"
    sign_in admin
  end

  it "vincula a apuração ao destino e redireciona" do
    post reconcile_inquiry_admin_lead_path(inquiry), params: { target_id: target.id }

    expect(response).to redirect_to(admin_lead_path(target))
    expect(Lead.find_by(id: inquiry.id)).to be_nil
    expect(target.activities.where(kind: "inquiry_reconciled").count).to eq(1)
    follow_redirect!
    expect(response.body).to include("Apuração vinculada")
  end

  it "rejeita destino fora do escopo com alerta" do
    other_tenant = Tenant.create!(name: "Outra #{SecureRandom.hex(3)}", slug: "outra-#{SecureRandom.hex(3)}")
    other = create(:lead, tenant: other_tenant)

    post reconcile_inquiry_admin_lead_path(inquiry), params: { target_id: other.id }

    expect(response).to redirect_to(admin_lead_path(inquiry))
    expect(Lead.find_by(id: inquiry.id)).to be_present
    follow_redirect!
    expect(response.body).to include("não encontrado no seu escopo")
  end

  it "rejeita registro que não é apuração" do
    plain = create(:lead, tenant: admin.tenant, admin_user: admin)

    post reconcile_inquiry_admin_lead_path(plain), params: { target_id: target.id }

    expect(response).to redirect_to(admin_lead_path(plain))
    expect(Lead.find_by(id: plain.id)).to be_present
  end

  it "aba A verificar lista só apurações não-verificadas" do
    inquiry
    create(:lead, tenant: admin.tenant, admin_user: admin)

    get admin_leads_path(view: "list", lead_tab: "verify")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("A verificar")
  end
end
