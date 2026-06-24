require "rails_helper"

RSpec.describe "Public navigation events", type: :request do
  before { host! "localhost" }

  describe "POST /navigation_events" do
    before do
      LayoutSetting.instance.update!(
        interest_intelligence_enabled: true,
        interest_intelligence_settings: InterestIntelligence::Settings::DEFAULTS.merge(
          "requires_public_tracking_consent" => false
        )
      )
    end

    it "records an anonymous property navigation event" do
      habitation = create(:habitation, cidade: "Balneário Camboriú", bairro: "Centro", dormitorios_qtd: 3)

      expect do
        post "/navigation_events",
          params: {
            navigation_event: {
              name: "property_view",
              path: "/imoveis/#{habitation.codigo}",
              habitation_id: habitation.id,
              search_params: { cidade: "Balneário Camboriú" },
              metadata: { title: "Apartamento no Centro" }
            }
          },
          as: :json
      end.to change(PublicNavigationSession, :count).by(1)
        .and change(PublicNavigationEvent, :count).by(1)

      expect(response).to have_http_status(:ok)
      event = PublicNavigationEvent.last
      expect(event.name).to eq("property_view")
      expect(event.habitation).to eq(habitation)
      expect(event.property_snapshot["city"]).to eq("Balneário Camboriú")
    end

    it "requires consent when public tracking consent is enabled" do
      LayoutSetting.instance.update!(
        interest_intelligence_settings: InterestIntelligence::Settings::DEFAULTS.merge(
          "requires_public_tracking_consent" => true
        )
      )

      expect do
        post "/navigation_events",
          params: {
            navigation_event: {
              name: "property_view",
              path: "/imoveis/123"
            }
          },
          as: :json
      end.not_to change(PublicNavigationEvent, :count)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("consent_required" => true)
    end

    it "rejects unknown event names" do
      expect do
        post "/navigation_events",
          params: {
            navigation_event: {
              name: "unexpected_event",
              path: "/imoveis/123"
            }
          },
          as: :json
      end.not_to change(PublicNavigationEvent, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
