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

  it "apresenta a identidade Grupo OLX preservando a origem usada pelas regras" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "grupo_zap")
    expect(origin(lead)).to include(brand: "buildings", label: "Grupo OLX")
    expect(lead.origin).to eq("grupo_zap")
    expect(helper.lead_origin_identity("Grupo OLX")).to eq(["buildings", "Grupo OLX", nil])
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
    expect(origin(lead)).to include(label: "WhatsApp", subtype: "Conversa", complements: [])
  end

  it "diferencia os subtipos do site e separa origem da conversão" do
    property = create(:habitation, tenant: tenant, codigo: "9001")

    form_lead = create(:lead, tenant: tenant, origin: "Site")
    SeoConversionEvent.create!(lead: form_lead, habitation: property, event_type: "lead_created", occurred_at: Time.current, source_path: "/imovel/9001")
    form_data = origin(form_lead, site_event: helper.lead_origin_site_events([form_lead], tenant: tenant)[form_lead.id])
    expect(form_data).to include(brand: "site", subtype: "Formulário do imóvel", complements: ["Imóvel #9001"])

    wa_lead = create(:lead, tenant: tenant, origin: "Google Ads", lead_type: "whatsapp_modal", source_url: "https://site.test/imovel/9001")
    SeoConversionEvent.create!(lead: wa_lead, habitation: property, event_type: "lead_created", occurred_at: Time.current, source_path: "/imovel/9001")
    wa_data = origin(wa_lead, site_event: helper.lead_origin_site_events([wa_lead], tenant: tenant)[wa_lead.id])
    expect(wa_data).to include(brand: "google", label: "Google Ads")
    expect(wa_data[:complements]).to include("Conversão: Site · WhatsApp do anúncio · Imóvel #9001")

    contact_lead = build_stubbed(:lead, tenant: tenant, origin: "Site", source_url: "https://site.test/contato")
    expect(origin(contact_lead)).to include(brand: "site", subtype: "Contato geral", complements: ["Página: /contato"])
  end

  it "separa origem Instagram da conversão no site com imóvel do anúncio" do
    property = create(:habitation, tenant: tenant, codigo: "1811")
    lead = create(:lead, tenant: tenant, origin: "Site", lead_type: "whatsapp_modal",
      source_url: "https://site.test/imoveis/apartamento-1811", attribution_source: "instagram")
    SeoConversionEvent.create!(lead: lead, habitation: property, event_type: "lead_created", occurred_at: Time.current, source_path: "/imoveis/apartamento-1811")
    data = origin(lead, site_event: helper.lead_origin_site_events([lead], tenant: tenant)[lead.id])

    expect(data).to include(brand: "instagram", label: "Instagram")
    expect(data[:complements]).to include("Conversão: Site · WhatsApp do anúncio · Imóvel #1811")
    expect(data[:details]).to include(["Origem registrada", "instagram"])
  end

  it "separa indicação do corretor da conversão no site" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "Compartilhamento Corretor",
      lead_type: "site", source_url: "https://site.test/contato")
    data = origin(lead, share_name: "Corretora Ana")

    expect(data).to include(brand: "share", label: "Indicação", subtype: "Corretora Ana")
    expect(data[:complements]).to include("Conversão: Site · Contato geral", "Página: /contato")
  end

  it "separa origem da importação como conversão" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "Migração externa",
      attribution_channel: "Internet", attribution_source: "Instagram Leads")
    data = origin(lead)

    expect(data).to include(brand: "instagram", label: "Instagram")
    expect(data[:complements]).to include("Conversão: Importação · Migração")
  end

  it "marca importação de planilha como conversão" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "Migração externa",
      attribution_channel: "Importado da planilha", attribution_source: "Google")
    data = origin(lead)

    expect(data).to include(label: "Google")
    expect(data[:complements]).to include("Conversão: Importação · Planilha")
  end

  it "exibe nome do buscador para código de atribuição em minúsculas" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "Google Ads", attribution_source: "google")

    expect(origin(lead)).to include(brand: "google", label: "Google")
  end

  it "trata origem direta em inglês como site puro" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "Site", lead_type: "site",
      source_url: "https://site.test/contato", attribution_source: "direct")
    data = origin(lead)

    expect(data).to include(brand: "site", subtype: "Contato geral")
    expect(data[:complements]).to eq(["Página: /contato"])
  end

  it "identifica o portal real do payload Grupo OLX com fallback genérico" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "grupo_zap", other_information: {
      "lead_origin" => "ZAP", "origin_listing_id" => "ABC123", "portal_lead_id" => "999"
    })
    data = origin(lead)
    expect(data).to include(brand: "zap", label: "ZAP Imóveis", subtype: "Portal")
    expect(data[:complements]).to include("Anúncio: ABC123")
    expect(data[:details]).to include(["Portal", "ZAP"])
    expect(lead.origin).to eq("grupo_zap")

    viva = build_stubbed(:lead, tenant: tenant, origin: "grupo_zap", other_information: {"lead_origin" => "VivaReal"})
    expect(origin(viva)).to include(brand: "vivareal", label: "VivaReal", subtype: "Portal")

    legacy = build_stubbed(:lead, tenant: tenant, origin: "VivaReal")
    expect(origin(legacy)).to include(label: "VivaReal", subtype: "Portal")

    generic = build_stubbed(:lead, tenant: tenant, origin: "grupo_zap")
    expect(origin(generic)).to include(brand: "buildings", label: "Grupo OLX")
  end

  it "resolve formulário público pelo slug com fallback humanizado" do
    PublicForm.ensure_default_site_forms!(tenant: tenant)
    form = tenant.public_forms.find_by!(slug: "trabalhe-conosco")

    lead = build_stubbed(:lead, tenant: tenant, origin: "public_form:trabalhe-conosco")
    names = helper.lead_origin_public_form_names([lead], tenant: tenant)
    data = origin(lead, public_form: names[lead.id])
    expect(data).to include(brand: "card-checklist", label: "Formulário #{form.name}", subtype: form.category)

    orphan = build_stubbed(:lead, tenant: tenant, origin: "public_form:contato_antigo")
    expect(origin(orphan)).to include(label: "Formulário contato antigo")
  end

  it "apresenta webhook genérico como integração com tags" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "webhook", other_information: {
      "webhook_tags" => ["parceria", "feirao"], "inbound_webhook_user_name" => "Maria"
    })
    data = origin(lead)
    expect(data).to include(brand: "plug", label: "Integração")
    expect(data[:complements]).to include("parceria", "feirao")
    expect(data[:details]).to include(["Recebido por", "Maria"])
  end

  it "apresenta importação genérica com canal e vendedor externo" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "Migração externa",
      attribution_data: {"provider" => "external_lead_migration", "channel" => {"name" => "Portais"}},
      other_information: {"external_lead_seller" => {"name" => "Carlos Silva"}})
    data = origin(lead)
    expect(data).to include(brand: "download", label: "Importação", subtype: "Portais")
    expect(data[:complements]).to include("Vendedor externo: Carlos Silva")
    expect(data[:details]).to include(["Entrada", "Importação"], ["Vendedor externo", "Carlos Silva"])
    expect(lead.origin).to eq("Migração externa")
  end

  it "apresenta indicação de corretor com o nome de quem indicou" do
    sharer = create(:admin_user, tenant: tenant, name: "Corretor Parceiro")
    lead = build_stubbed(:lead, tenant: tenant, origin: "Compartilhamento Corretor", shared_by_admin_user_id: sharer.id)
    names = helper.lead_origin_share_names([lead], tenant: tenant)
    data = origin(lead, share_name: names[lead.id])
    expect(data).to include(brand: "share", label: "Indicação", subtype: "Corretor Parceiro")
  end

  it "detecta RD e Lovers pelo canal mesmo com origem renomeada" do
    rd = build_stubbed(:lead, tenant: tenant, origin: "RD Custom", other_information: {
      "rd_station_event_type" => "WEBHOOK.CONVERTED",
      "rd_station_conversion_identifier" => "Landing Praia"
    })
    expect(origin(rd)).to include(brand: "rdstation", label: "RD Station", subtype: "Conversão")

    lovers = build_stubbed(:lead, tenant: tenant, origin: "Base antiga", other_information: {
      "lovers_code" => "123", "lovers_status" => "Ativo"
    })
    expect(origin(lovers)).to include(brand: "lovers", label: "Lovers", subtype: "Importação")
  end

  it "usa evento original do site mesmo após troca do imóvel atual" do
    lead = create(:lead, tenant: tenant, origin: "Google Ads", lead_type: "whatsapp_modal", source_url: "https://site.test/imovel?token=secret")
    original = create(:habitation, tenant: tenant, codigo: "4148")
    event = SeoConversionEvent.create!(lead: lead, habitation: original, event_type: "lead_created", occurred_at: 1.day.ago, source_path: "/imovel/4148?token=secret")
    lead.update_column(:property_id, create(:habitation, tenant: tenant).id)
    data = origin(lead, site_event: helper.lead_origin_site_events([lead], tenant: tenant)[lead.id])
    expect(data).to include(brand: "google", label: "Google Ads")
    expect(data[:complements]).to eq(["Conversão: Site · WhatsApp do anúncio · Imóvel #4148"])
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
    expect(origin(lead, site_event: event)[:complements]).to eq(["Conversão: Site · Contato geral", "Página: /contato"])
  end

  it "mostra a página do modal sem usar o imóvel atualmente vinculado" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "Google Ads", lead_type: "whatsapp_modal", source_url: "https://site.test/contato?email=secret", property_id: 123)
    expect(origin(lead)).to include(brand: "google", complements: ["Conversão: Site · WhatsApp do site", "Página: /contato"])
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

  it "não quebra a coluna com lead de migração cujo channel/lead_source são strings" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "Site",
      other_information: { "source" => "external_lead_migration" },
      attribution_data: { "channel" => "google_ads", "lead_source" => "c2s" })

    expect { origin(lead) }.not_to raise_error
  end

  it "não quebra a fonte da importação com payloads aninhados em formato string" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "Migração externa")

    expect do
      helper.lead_origin_import_source(
        lead,
        { "attributes" => "c2s", "c2s_payload" => "ping" },
        { "lead_source" => "c2s" }
      )
    end.not_to raise_error
  end

  it "dá preferência à Meta sobre o carimbo RD, com RD como contexto de conversão" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "RD Station",
      attribution_channel: "meta_ads", attribution_source: "meta",
      other_information: {
        "rd_station_event_type" => "WEBHOOK.CONVERTED",
        "rd_station_conversion_identifier" => "Form - Refuge",
        "rd_station_campaign_name" => "[KD] Refuge [Leads]",
        "meta_form_name" => "Form - Refuge"
      })

    data = origin(lead)

    expect(data).to include(label: "Meta Ads", subtype: "Formulários")
    expect(data[:complements]).to include("Conversão: RD Station · Form - Refuge", "Campanha: [KD] Refuge [Leads]")
    expect(data[:details]).to include(["Conversão RD", "Form - Refuge"], ["Campanha RD", "[KD] Refuge [Leads]"])
  end

  it "dá preferência ao Instagram sobre o carimbo RD" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "RD Station",
      attribution_channel: "Internet", attribution_source: "Instagram Leads",
      other_information: {
        "rd_station_event_type" => "WEBHOOK.CONVERTED",
        "rd_station_conversion_identifier" => "Form - Refuge"
      })

    data = origin(lead)

    expect(data).to include(label: "Instagram")
    expect(data[:complements]).to include("Conversão: RD Station · Form - Refuge")
  end

  it "mantém RD Station como rótulo sem evidência Meta (guardrail)" do
    lead = build_stubbed(:lead, tenant: tenant, origin: "RD Station",
      other_information: {
        "rd_station_event_type" => "WEBHOOK.CONVERTED",
        "rd_station_conversion_identifier" => "Form - Refuge",
        "rd_station_campaign_name" => "[KD] Refuge [Leads]"
      })

    data = origin(lead)

    expect(data).to include(label: "RD Station", subtype: "Conversão")
    expect(data[:complements]).to include(
      "Campanha: [KD] Refuge [Leads]", "Conversão: Form - Refuge"
    )
  end
end
