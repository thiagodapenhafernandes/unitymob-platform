require "rails_helper"

RSpec.describe "Admin lead interest intelligence", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, :admin, email: "lead-interest-#{SecureRandom.hex(6)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
    LayoutSetting.instance.update!(
      interest_intelligence_enabled: true,
      interest_intelligence_settings: InterestIntelligence::Settings::DEFAULTS.merge(
        "minimum_match_score" => 50,
        "max_suggestions" => 3
      )
    )
  end

  def create_interest_context
    viewed_property = create(
      :habitation,
      titulo_anuncio: "Apartamento Centro visitado",
      categoria: "Apartamento",
      cidade: "Balneário Camboriú",
      bairro: "Centro",
      dormitorios_qtd: 3,
      valor_venda_cents: 1_200_000_00
    )
    create(
      :habitation,
      titulo_anuncio: "Apartamento Centro compatível",
      categoria: "Apartamento",
      cidade: "Balneário Camboriú",
      bairro: "Centro",
      dormitorios_qtd: 3,
      valor_venda_cents: 1_250_000_00
    )
    lead = create(:lead, admin_user: admin, property_id: viewed_property.id, status: "Em Atendimento")
    session = PublicNavigationSession.create!(lead: lead, token: SecureRandom.uuid)
    PublicNavigationEvent.create!(
      public_navigation_session: session,
      lead: lead,
      habitation: viewed_property,
      name: "property_view",
      path: "/imoveis/#{viewed_property.codigo}",
      occurred_at: 5.minutes.ago,
      property_snapshot: {
        city: "Balneário Camboriú",
        neighborhood: "Centro",
        category: "Apartamento",
        bedrooms: 3,
        price_cents: 1_200_000_00
      }
    )

    lead
  end

  describe "GET show" do
    it "mostra a inteligência de interesse e sugestões compatíveis" do
      lead = create_interest_context

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Inteligência de Interesse")
      expect(response.body).to include("imóveis vistos")
      expect(response.body).to include("Apartamento Centro compatível")
      expect(response.body).to include("Reprocessar")
      expect(response.body).to include("Simular")
    end
  end

  describe "POST simulate_interest" do
    it "renderiza a simulação sem disparar eventos de automação" do
      lead = create_interest_context
      AutomationEvent.delete_all

      expect {
        post simulate_interest_admin_lead_path(lead)
      }.not_to change(AutomationEvent, :count)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Simulação calculada agora")
      expect(response.body).to include("Apartamento Centro compatível")
    end
  end

  describe "POST reprocess_interest" do
    it "gera sinais de interesse e eventos para o builder" do
      lead = create_interest_context
      AutomationEvent.delete_all

      expect {
        post reprocess_interest_admin_lead_path(lead)
      }.to change(ClientPropertyInterest, :count).by(1)
        .and change(AutomationEvent, :count).by(2)
        .and have_enqueued_job(Automation::ProcessEventJob).twice

      expect(response).to redirect_to(admin_lead_path(lead))
      expect(AutomationEvent.pluck(:name)).to include("interest_profile_detected", "matching_property_found")
      expect(LeadActivity.where(lead: lead, kind: "interest_reprocessed")).to exist
    end
  end
end
