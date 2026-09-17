require "rails_helper"

RSpec.describe Admin::LeadOriginHelper, type: :helper do
  before do
    helper.extend Admin::ComercialHelper
    helper.extend Admin::LeadTableHelper
  end

  let(:tenant) { Tenant.default }
  def origin(lead, **options)
    helper.lead_origin_column(lead, tenant: tenant, **options)
  end

  it "distingue plataformas CTWA, sem presumir orgânico pela ausência de referência" do
    {
      "CTWA Instagram" => ["instagram", "Instagram", "CTWA"],
      "CTWA Facebook - Anúncios" => ["facebook", "Facebook", "CTWA"],
      "WhatsApp CTWA" => ["whatsapp", "WhatsApp", "CTWA"],
      "WhatsApp Orgânico" => ["whatsapp", "WhatsApp", "Orgânico"],
      "WhatsApp" => ["whatsapp", "WhatsApp", nil],
      "Instagram Leads" => ["instagram", "Instagram", "Leads"],
      "Facebook" => ["meta", "Facebook", nil]
    }.each do |raw, expected|
      expect(helper.lead_origin_identity(raw, ctwa: raw.include?("CTWA"))).to eq(expected)
    end
  end

  it "exibe o anúncio recebido sem inventar plataforma ou nome de campanha" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "whatsapp", other_information: {
      "whatsapp_entry" => {"referral" => {"source_type" => "ad", "source_id" => "123456", "headline" => "Conheça a unidade"}}
    })
    expect(origin(lead)).to include(label: "WhatsApp", subtype: "CTWA", complements: ["Anúncio: Conheça a unidade"])
    lead.other_information["whatsapp_entry"]["referral"].delete("headline")
    expect(origin(lead)[:complements]).to eq(["Anúncio ID: 123456"])
  end

  it "não trata referral de publicação como anúncio CTWA" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "whatsapp", other_information: {
      "whatsapp_entry" => {"referral" => {"source_type" => "post", "source_id" => "123456"}}
    })
    expect(origin(lead)).to include(subtype: nil, complements: [])
  end

  it "usa evento original do site mesmo após troca do imóvel atual" do
    lead = create(:lead, tenant: tenant, origin: "Google Ads", lead_type: "whatsapp_modal", source_url: "https://site.test/imovel?token=secret")
    original = create(:habitation, tenant: tenant, codigo: "4148")
    event = SeoConversionEvent.create!(lead: lead, habitation: original, event_type: "lead_created", occurred_at: 1.day.ago, source_path: "/imovel/4148?token=secret")
    lead.update_column(:property_id, create(:habitation, tenant: tenant).id)
    data = origin(lead, site_event: helper.lead_origin_site_events([lead], tenant: tenant)[lead.id])
    expect(data[:brand]).to eq("site")
    expect(data[:complements]).to eq(["Imóvel #4148"])
    expect(data[:details]).to include(["Origem registrada", "Google Ads"], ["Página", "/imovel/4148"])
    expect(data.to_s).not_to include("secret")
    expect(event.reload.habitation_id).to eq(original.id)
  end

  it "não usa clique, visita posterior, evento de outro lead ou imóvel de outra conta" do
    lead = create(:lead, tenant: tenant, origin: "ZAP Imóveis", source_url: nil)
    SeoConversionEvent.create!(lead: lead, event_type: "whatsapp_click", occurred_at: Time.current)
    expect(helper.lead_origin_site_events([lead], tenant: tenant)).to be_empty
    foreign = Tenant.create!(name: "Outra", slug: "origin-foreign")
    other_lead = create(:lead, tenant: foreign)
    event = SeoConversionEvent.create!(lead: other_lead, event_type: "lead_created", occurred_at: Time.current)
    expect(origin(lead, site_event: event)[:label]).to eq("ZAP Imóveis")
    expect(helper.lead_origin_column(lead, tenant: foreign)).to be_nil
    event.update!(lead: lead, habitation: create(:habitation, tenant: foreign), source_path: "/contato")
    expect(origin(lead, site_event: event)[:complements]).to eq(["Página: /contato"])
  end

  it "mostra a página do modal sem usar o imóvel atualmente vinculado" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "Google Ads", lead_type: "whatsapp_modal", source_url: "https://site.test/contato?email=secret", property_id: 123)
    expect(origin(lead)).to include(brand: "site", complements: ["Página: /contato"])
    lead.origin = "Internet"
    lead.lead_type = nil
    expect(origin(lead)[:brand]).not_to eq("site")
  end

  it "resolve nomes dos sites a partir da identidade da conta e mantém fallback" do
    allow(helper).to receive(:lead_origin_layout).and_return(nil)
    tenant.name = "Salute Imóveis"
    expect(helper.lead_origin_site_name(tenant)).to eq("Salute Imóveis")
    tenant.name = "Conexão Imobiliária"
    expect(helper.lead_origin_site_name(tenant)).to eq("Conexão BC")
    tenant.name = "Outra imobiliária"
    expect(helper.lead_origin_site_name(tenant)).to eq("Outra imobiliária")
  end

  it "preserva portais, origens personalizadas e integrações sem presumir conexão ativa" do
    {"ZAP Imóveis" => "zap", "Imovelweb" => "imovelweb", "VivaReal" => "vivareal", "Grupo Zap" => "buildings", "RD Station API" => "rdstation", "Cadastro manual" => "person-plus", "Showroom Atlântica" => "shop", "Parceiro local" => "tag"}.each do |raw, brand|
      expect(origin(build_stubbed(:lead, tenant: tenant, origin: raw))[:brand]).to eq(brand)
    end
  end

  it "mantém origem específica e mascara o fornecedor inclusive nos detalhes" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "C2S", attribution_source: "WhatsApp Orgânico", attribution_data: {"provider" => "external_lead_migration"}, other_information: {"campaign_name" => "Campanha C2S"})
    data = origin(lead)
    expect(data).to include(label: "WhatsApp", subtype: "Orgânico")
    expect(data.to_s).not_to match(/c2s/i)
    expect(lead.origin).to eq("C2S")
  end

  it "mantém Meta compacto e preserva formulário, campanha e anúncio nos detalhes" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "Meta Ads", other_information: {
      "meta_form_id" => "123456", "meta_campaign_name" => "Solar Elisa", "meta_ad_name" => "Apartamento"
    })
    data = origin(lead)
    expect(data).to include(label: "Meta Ads", brand: "meta", subtype: "Formulários", complements: [])
    expect(data[:details]).to include(["Formulário", "123456"], ["Campanha", "Solar Elisa"], ["Anúncio", "Apartamento"])
    expect(origin(lead, form_name: "Form Solar Elisa")[:details]).to include(["Formulário", "Form Solar Elisa"])
  end

  it "exibe RD Station com a ação original da conversão" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "RD Station", lead_type: "rd_station", other_information: {
      "rd_station_event_type" => "WEBHOOK.CONVERTED",
      "rd_station_conversion_identifier" => "Landing Praia",
      "rd_station_campaign_name" => "Campanha Praia",
      "rd_station_source" => "newsletter",
      "rd_station_medium" => "email"
    })

    data = origin(lead)

    expect(data).to include(label: "RD Station", brand: "rdstation", subtype: "Conversão")
    expect(data[:complements]).to include("Campanha: Campanha Praia", "Conversão: Landing Praia", "Origem original: newsletter / email")
    expect(data[:details]).to include(["Evento RD", "WEBHOOK.CONVERTED"], ["Conversão RD", "Landing Praia"], ["Campanha RD", "Campanha Praia"], ["Origem RD", "newsletter / email"])
  end

  it "exibe Lovers como fonte reconhecida com dados da importação" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "Lovers", lead_type: "lovers", other_information: {
      "lovers_code" => "123",
      "lovers_status" => "Ativo",
      "lovers_score" => "10",
      "lovers_source" => "Landing Praia",
      "lovers_registration_date" => "2026-09-16T10:00:00"
    })

    data = origin(lead)

    expect(data).to include(label: "Lovers", brand: "lovers", subtype: "Importação")
    expect(data[:complements]).to include("Origem original: Landing Praia", "Status: Ativo", "Score: 10")
    expect(data[:details]).to include(["Código Lovers", "123"], ["Status Lovers", "Ativo"], ["Score Lovers", "10"], ["Cadastro Lovers", "2026-09-16T10:00:00"])
  end
end
