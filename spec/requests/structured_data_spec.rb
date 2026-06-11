require "rails_helper"

RSpec.describe "Structured data", type: :request do
  before { host! "localhost" }

  it "renders the RealEstateAgent JSON-LD on the home page" do
    get root_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    script = document.at_css("head script[type='application/ld+json']")
    payload = JSON.parse(script.text)

    expect(payload["@type"]).to eq(["RealEstateAgent", "LocalBusiness"])
    expect(payload["name"]).to eq("Salute Imóveis")
    expect(payload["logo"]).to start_with("http://localhost/assets/")
    expect(payload["logo"]).to include("salute-imoveis")
    expect(payload["location"].size).to eq(2)
  end
end
