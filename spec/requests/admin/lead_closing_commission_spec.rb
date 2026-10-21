require "rails_helper"

RSpec.describe "Comissão real no fechamento", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:lead) { create(:lead, tenant: admin.tenant, admin_user: admin) }
  before do
    host! "localhost"
    sign_in admin
  end
  it "salva a comissão antes do fechamento e a registra na auditoria" do
    post close_deal_admin_lead_path(lead), params: { lead: { closing_commission: "1.250,50", tenant_id: 99999 } }
    expect(response).to redirect_to(admin_lead_path(lead))
    expect(lead.reload.closing_commission_cents).to eq(125050)
    expect(lead.tenant_id).to eq(admin.tenant_id)
    expect(lead.lead_audit_logs.order(:id).last.changeset).to have_key("closing_commission_cents")
  end
  it "não fecha nem apaga valores diante de uma comissão inválida" do
    original = lead.status
    post close_deal_admin_lead_path(lead), params: { lead: { closing_commission: "-100" } }
    expect(lead.reload.status).to eq(original)
    expect(lead.closing_commission_cents).to be_nil
    expect(flash[:alert]).to be_present
  end
  it "exibe o mesmo campo de fechamento no desktop e no painel mobile" do
    get admin_lead_path(lead)
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    fields = document.css('input[name="lead[closing_commission]"]')
    expect(fields.size).to be >= 1
    expect(fields.map { |field| field["id"] }.uniq.size).to eq(fields.size)
  end

end
