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
    event = PublicNavigationEvent.create!(
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

    [lead, event]
  end

  describe "GET show" do
    it "carrega a inteligência de interesse por frame lazy" do
      lead, = create_interest_context

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Inteligência de Interesse")
      expect(response.body).to include(interest_intelligence_admin_lead_path(lead))
      expect(response.body).to include("Carregando sinais")
    end
  end

  describe "GET interest_intelligence" do
    it "mostra sinais e sugestões compatíveis no frame, sem botões manuais" do
      lead, = create_interest_context

      get interest_intelligence_admin_lead_path(lead), headers: { "Turbo-Frame" => ActionView::RecordIdentifier.dom_id(lead, :interest_intelligence) }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("imóveis vistos")
      expect(response.body).to include("Apartamento Centro compatível")
      # perfil/matches recalculam sozinhos a cada carregamento — não existe
      # mais botão manual de reprocessar nem de simular.
      expect(response.body).not_to include("Reprocessar")
      expect(response.body).not_to include(">Simular<")
    end
  end

  describe "reprocessamento automático via navegação nova" do
    it "um evento de navegação de um lead existente enfileira o ReprocessJob" do
      _lead, event = create_interest_context

      expect { InterestIntelligence::ReprocessJob.perform_later(event.lead_id) }
        .to have_enqueued_job(InterestIntelligence::ReprocessJob).with(event.lead_id)
    end

    it "rodar o job gera sinais de interesse e eventos de automação, sem registrar isso na Linha do tempo" do
      lead, = create_interest_context
      AutomationEvent.delete_all

      expect { perform_enqueued_jobs { InterestIntelligence::ReprocessJob.perform_later(lead.id) } }
        .to change(ClientPropertyInterest, :count).by(1)
        .and change(AutomationEvent, :count).by(2)

      expect(AutomationEvent.pluck(:name)).to include("interest_profile_detected", "matching_property_found")
      # a entrada "interest_reprocessed" na Linha do tempo principal foi
      # removida por não ter valor prático pra operação.
      expect(LeadActivity.where(lead: lead, kind: "interest_reprocessed")).not_to exist
    end
  end
end
