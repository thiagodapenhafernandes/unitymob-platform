require "rails_helper"

RSpec.describe Leads::Attribution do
  it "não rotula como orgânico um meio pago sem plataforma informada" do
    lead = build(:lead)
    described_class.apply!(lead, raw: {utm_medium: "cpc", referrer_url: "https://www.google.com/"})
    expect(lead.attribution_channel).to eq("paid_campaign")
    expect(lead.attribution_source).to eq("unknown")
  end

  it "preserva identificadores externos de campanha para conciliação posterior" do
    lead = build(:lead)

    described_class.apply!(lead, raw: { utm_id: "meta-123", gad_campaignid: "google-456", gbraid: "braid-789" })

    expect(lead.attribution_data).to include("utm_id" => "meta-123", "gad_campaignid" => "google-456", "gbraid" => "braid-789")
  end

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

RSpec.describe Leads::Attribution, "attribution v2" do
  def classify(raw)
    described_class.new(raw: raw, request: Struct.new(:host).new("imobiliaria.example")).result
  end

  { gclid: "google_ads", gbraid: "google_ads", wbraid: "google_ads", msclkid: "microsoft_ads", ttclid: "tiktok_ads" }.each do |key, channel|
    it "reconhece #{key} e registra a evidência" do
      result = classify(key => "Click-123")
      expect(result.channel).to eq(channel)
      expect(result.data).to include("evidence" => "click_id:#{key}", key.to_s => "Click-123")
    end
  end

  it "não transforma fbclid em prova de Meta Ads" do
    result = classify(fbclid: "click")
    expect(result.channel).to eq("social")
    expect(result.source).to eq("meta")
    expect(result.data["confidence"]).to eq("inferred")
  end

  { "facebook" => "meta_ads", "instagram" => "meta_ads", "bing" => "microsoft_ads", "tiktok" => "tiktok_ads",
    "linkedin" => "linkedin_ads", "pinterest" => "pinterest_ads", "twitter" => "x_ads", "youtube" => "youtube_ads", "parceiro" => "paid_campaign" }.each do |source, channel|
    it "reconhece mídia paga declarada de #{source}" do
      expect(classify(utm_source: source, utm_medium: "paid_social").channel).to eq(channel)
    end
  end

  it "não reconhece paid dentro de unpaid nem google dentro de outra fonte" do
    expect(classify(utm_source: "google", utm_medium: "unpaid").channel).to eq("campaign")
    expect(classify(utm_source: "notgoogle", utm_medium: "cpc").channel).to eq("paid_campaign")
  end

  %w[google.com.evil.test fakebing.com evil.google.test].each do |host|
    it "não confunde #{host} com domínio de busca" do
      expect(classify(referrer_url: "https://#{host}/").channel).to eq("referral")
    end
  end

  it "reconhece Google e Bing orgânicos por referência e UTM" do
    expect(classify(referrer_url: "https://www.google.com.br/search").channel).to eq("organic_search")
    expect(classify(referrer_url: "https://www.bing.com/search").label).to eq("Bing orgânico")
    expect(classify(utm_source: "google", utm_medium: "organic").channel).to eq("organic_search")
  end

  it "preserva qual rede social enviou o visitante sem presumir mídia paga" do
    %w[facebook instagram tiktok linkedin pinterest youtube].each do |source|
      result = classify(referrer_url: "https://www.#{source}.com/post")
      expect(result.source).to eq(source)
      expect(result.channel).to eq("social")
    end
  end

  it "reconhece e-mail, mensagens e outras campanhas" do
    expect(classify(utm_source: "newsletter", utm_medium: "email").channel).to eq("email")
    expect(classify(utm_source: "whatsapp", utm_medium: "messaging").channel).to eq("messaging")
    expect(classify(utm_source: "parceiro", utm_medium: "referral").channel).to eq("campaign")
  end

  it "não usa a própria imobiliária como referência externa" do
    expect(classify(referrer_url: "https://www.imobiliaria.example/imovel").channel).to eq("direct")
  end

  it "não escolhe um anúncio arbitrariamente quando identificadores conflitam" do
    result = classify(gclid: "google", ttclid: "tiktok")
    expect(result.data["evidence"]).to eq("conflicting_click_ids")
    expect(result.channel).to eq("direct")
  end

  it "separa primeira chegada e sessão da conversão sem sobrescrever origem de negócio" do
    lead = build(:lead, origin: "Compartilhamento Corretor")
    described_class.apply!(lead, raw: {
      first_touch: { gclid: "first" }, conversion_touch: { ttclid: "last", utm_campaign: "campanha" }
    })
    expect(lead.attribution_channel).to eq("tiktok_ads")
    expect(lead.attribution_data.dig("first_touch", "channel")).to eq("google_ads")
    expect(lead.attribution_data.dig("conversion_touch", "channel")).to eq("tiktok_ads")
    expect(lead.attribution_data["gclid"]).to be_nil
    expect(lead.origin).to eq("Compartilhamento Corretor")
  end

  it "ignora estruturas malformadas e não aceita evidência enviada pelo cliente" do
    result = classify(gclid: { value: "fake" }, evidence: "verified", landing_url: "https://user:password@example.com")
    expect(result.data).to eq({})
  end
end
