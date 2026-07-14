require "rails_helper"

RSpec.describe Leads::Attribution do
  subject(:lead) { build(:lead, origin: "") }

  it "classifica Google Ads e preserva os dados de primeira entrada" do
    described_class.apply!(lead, raw: {
      landing_url: "https://site.example/imoveis?utm_source=google&utm_medium=cpc",
      referrer_url: "https://www.google.com/",
      utm_source: "google",
      utm_medium: "cpc",
      utm_campaign: "aluguel",
      gclid: "click-123"
    })

    expect(lead).to have_attributes(
      attribution_channel: "google_ads",
      attribution_source: "google",
      origin: "Google Ads"
    )
    expect(lead.attribution_data).to include(
      "utm_campaign" => "aluguel",
      "gclid" => "click-123",
      "referrer_url" => "https://www.google.com/"
    )
  end

  it "classifica busca orgânica sem confundir o modal de WhatsApp com a aquisição" do
    lead.lead_type = "whatsapp_modal"

    described_class.apply!(lead, raw: {
      landing_url: "https://site.example/imoveis/123",
      referrer_url: "https://www.google.com/"
    })

    expect(lead).to have_attributes(
      attribution_channel: "organic_search",
      attribution_source: "google",
      origin: "Google orgânico"
    )
  end

  it "mantém uma origem de negócio já atribuída" do
    lead.origin = "Compartilhamento Corretor"

    described_class.apply!(lead, raw: { landing_url: "https://site.example/", gclid: "click-123" })

    expect(lead.origin).to eq("Compartilhamento Corretor")
    expect(lead.attribution_channel).to eq("google_ads")
  end

  it "descarta URLs inválidas" do
    described_class.apply!(lead, raw: { landing_url: "javascript:alert(1)", referrer_url: "inválida" })

    expect(lead.attribution_data).not_to include("landing_url", "referrer_url")
  end
end
