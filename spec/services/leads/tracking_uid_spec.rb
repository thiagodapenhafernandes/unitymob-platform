require "rails_helper"

RSpec.describe Leads::TrackingUid do
  let(:request) { double(cookies: { "user_id_mh" => "Cookie_Ab%2F+" }, query_parameters: { "utm_content" => "query" }, referer: "https://site.test/?utm_content=page") }

  it "prioriza cookie, campo e URL sem normalizar o identificador" do
    expect(described_class.capture(raw: { utm_content: "hidden" }, request: request)).to eq("Cookie_Ab%2F+")
    allow(request).to receive(:cookies).and_return({})
    expect(described_class.capture(raw: { utm_content: "Hidden_Ab+%2F" }, request: request)).to eq("Hidden_Ab+%2F")
    expect(described_class.capture(raw: {}, request: request)).to eq("query")
    expect(described_class.capture(raw: { landing_url: "https://site.test/?utm_content=UID_123" })).to eq("UID_123")
    expect(described_class.capture(raw: { landing_url: "http://[" })).to be_nil
    expect(described_class.capture(raw: { landing_url: "https://site.test/?utm_content=%ZZ" })).to be_nil
    uid = " Ab%2F+" + "x" * 1100
    expect(described_class.capture(raw: { utm_content: uid })).to eq(uid)
  end

  it "mantém o primeiro UID e acumula novas entradas sem duplicação" do
    original = { "tracking_uid" => "First", "tracking_uids" => ["First"], "utm_source" => "google" }
    merged = described_class.merge(original, { "tracking_uid" => "Second" })
    expect(merged).to include("tracking_uid" => "First", "tracking_uids" => %w[First Second], "utm_source" => "google")
    expect(described_class.merge(merged, { "tracking_uid" => "Second" })).to eq(merged)
    expect(original["tracking_uids"]).to eq(["First"])
  end

  it "protege o UID em edições sem reclassificar a origem" do
    lead = create(:lead, origin: "Indicação", attribution_data: { "tracking_uid" => "First", "tracking_uids" => ["First"] })
    lead.update!(attribution_data: { "tracking_uid" => "Edited" })
    expect(lead.reload.attribution_data).to include("tracking_uid" => "First", "tracking_uids" => ["First"])
    expect(lead.origin).to eq("Indicação")
  end

  it "mantém a primeira origem ao receber nova atribuição" do
    lead = build(:lead, origin: "Google Ads", attribution_data: { "first_touch" => { "gclid" => "initial" } })
    Leads::Attribution.apply!(lead, raw: { utm_content: "UID_New", first_touch: { ttclid: "later" } })
    expect(lead.origin).to eq("Google Ads")
    expect(lead.attribution_data["first_touch"]).to eq("gclid" => "initial")
  end

  it "omite ambos os campos quando não há UID" do
    expect(described_class.payload({})).to eq({})
  end
end
