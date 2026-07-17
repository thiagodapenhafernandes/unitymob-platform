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
    expect(payload["logo"]).to start_with("http://localhost/") if payload["logo"].present?
    expect(payload["location"]).to be_present
  end

  it "uses the dynamic PWA icon as the public social image fallback" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(property="og:image" content="https://localhost/pwa-icon-512?v=))
    expect(response.body).to include(%(name="twitter:image" content="https://localhost/pwa-icon-512?v=))
    expect(response.body).to include(%(property="og:image:type" content="image/png"))
    expect(response.body).to include(%(property="og:image:width" content="512"))
    expect(response.body).to include(%(property="og:image:height" content="512"))
    expect(response.body).to include(%(rel="icon" type="image/png" sizes="192x192" href="/pwa-icon-192?v=))
  end
end
