require "rails_helper"

RSpec.describe "Modal Jornada do lead", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:lead) { create(:lead, tenant: admin.tenant, admin_user: admin) }
  before do
    host! "localhost"
    sign_in admin
  end

  it "mantém a ficha sem abas e abre a jornada pelo modal ao lado do histórico" do
    get admin_lead_path(lead)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('#lead-attendance-tab')).to be_nil
    expect(doc.at_css('[data-ax-modal-open="#leadAuditHistoryModal"]').next_element['data-ax-modal-open']).to eq('#leadJourneyModal')
    expect(doc.at_css('#leadJourneyModal')['hidden']).not_to be_nil
    expect(doc.at_css('#leadJourneyModal turbo-frame')['loading']).to eq('lazy')
    expect(doc.at_css('#lead-attendance .lead-next-action-card')).to be_present
    expect(doc.at_css('.lead-pwa-detail #leadJourneyModal')).to be_nil
    expect(doc.at_css('.lead-pwa-detail')).to be_present
  end

  it "renderiza evidências escapadas somente do lead autorizado" do
    lead.activities.create!(kind: "distributed", metadata: { body: '<script>alert(1)</script>', by: admin.name })
    get journey_admin_lead_path(lead)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Jornada do atendimento', 'Uma jornada, três perspectivas')
    payload = JSON.parse(Nokogiri::HTML(response.body).at_css('[data-controller="ax-journey"]')['data-ax-journey-data-value'])
    expect(payload['milestones'].find { |m| m['key'] == 'distribution' }['evidence'].first['detail']).to include('<script>')
    expect(response.body).not_to include('<script>alert(1)</script>')
    expect(response.body).to include('Sem evidência registrada')
  end

  it "não permite consultar lead de outra conta" do
    other = create(:lead, tenant: Tenant.create!(name: "Jornada externa", slug: "journey-external-#{SecureRandom.hex(4)}"))
    get journey_admin_lead_path(other)
    expect(response).to have_http_status(:not_found)
  end
  it "reaproveita a restrição de acesso do corretor ao lead" do
    agent = create(:admin_user, tenant: admin.tenant)
    agent.profile.update!(permissions: { "leads" => { "view" => true, "scope" => "own" } })
    agent.update!(horizontal_profile: nil)
    sign_in agent
    get journey_admin_lead_path(lead)
    expect(response).to redirect_to(admin_leads_path)
    expect(response.body).not_to include("Jornada do atendimento")
  end

end
