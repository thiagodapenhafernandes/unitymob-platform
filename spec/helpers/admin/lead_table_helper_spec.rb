require "rails_helper"

RSpec.describe Admin::LeadTableHelper, type: :helper do
  it "usa o primeiro interesse somente quando não há imóvel principal" do
    lead = create(:lead)
    first_property = create(:habitation, tenant: lead.tenant)
    second_property = create(:habitation, tenant: lead.tenant)
    lead.property_interests.create!(tenant: lead.tenant, habitation: first_property, created_at: 2.days.ago)
    lead.property_interests.create!(tenant: lead.tenant, habitation: second_property, created_at: 1.day.ago)
    expect(helper.lead_table_interest_properties([lead], tenant: lead.tenant)).to eq(lead.id => first_property)
    lead.property_id = second_property.id
    expect(helper.lead_table_interest_properties([lead], tenant: lead.tenant)).to be_empty
    lead.property_id = nil
    other = Tenant.create!(name: "Outra conta", slug: "other-interest-account")
    expect(helper.lead_table_interest_properties([lead], tenant: other)).to be_empty
    lead.property_interests.destroy_all
    expect(helper.lead_table_interest_properties([lead], tenant: lead.tenant)).to be_empty
  end

  it "resolve formulário local sem conta de anúncios e ignora outras contas" do
    integration = create(:user_meta_integration)
    page = create(:meta_facebook_page, user_meta_integration: integration)
    create(:meta_lead_form, meta_facebook_page: page, form_id: "12345", name: "Nome sincronizado")
    other = Tenant.create!(name: "Outro tenant", slug: "other-form-tenant")
    foreign_integration = create(:user_meta_integration, tenant: other)
    foreign_page = create(:meta_facebook_page, user_meta_integration: foreign_integration)
    create(:meta_lead_form, meta_facebook_page: foreign_page, form_id: "12345", name: "Nome de outra conta")
    lead = build_stubbed(:lead, tenant: integration.tenant, other_information: {"meta_form_id" => "12345"})
    names = helper.lead_table_meta_form_names([lead], tenant: integration.tenant)
    expect(names[lead.id]).to eq("Nome sincronizado")
    expect(helper.lead_table_conversion(lead, {}, form_name: names[lead.id])[:label]).to eq("Formulário: Nome sincronizado")
  end

  it "identifica a extensão em roxo sem alterar outros cadastros WhatsApp" do
    lead = build(:lead, origin: "WhatsApp", other_information: {"creation_source" => "browser_extension"})
    expect(helper.lead_table_conversion(lead, {})).to include(label: "Cadastro: Extensão Unitymob", icon: "puzzle", tone: :purple)
    lead.other_information = {}
    expect(helper.lead_table_conversion(lead, {conversion_origin_label: "WhatsApp"})[:label]).to eq("Conversão: WhatsApp")
  end

  it "distingue os seis status e mantém o alias Novo Lead" do
    statuses = ["Novo", "Em Atendimento", "Aguardando Aceite", "Represado", "Descartado", "Concluido"]
    expect(statuses.map { |status| helper.lead_table_status_tone(status) }).to eq(%i[cyan blue amber gray red green])
    expect(helper.lead_table_status_tone("Novo Lead")).to eq(:cyan)
    expect(helper.lead_table_status_tone("Personalizado")).to eq(:gray)
  end

  it "exibe somente características conhecidas do imóvel" do
    lead = build(:lead)
    allow(lead).to receive(:business_label).and_return(nil)
    property = Habitation.new(status: "Aluguel", categoria: "Apartamento", dormitorios_qtd: 3,
      suites_qtd: 1, vagas_qtd: 0, area_privativa_m2: nil)
    expect(helper.lead_table_property_badges(lead, property)).to eq([
      ["Locação", :green], ["Apartamento", :gray], ["3 dorm.", :gray], ["1 suíte", :gray]
    ])
    expect(helper.lead_table_property_badges(lead, nil)).to eq([])
  end

  it "identifica o formulário Meta e a campanha recebida sem duplicar Canal Meta Ads" do
    lead = build(:lead, product: "Apartamentos Barra Sul", other_information: {
      "meta_form_id" => "123", "campaign_name" => "Lançamento"
    })
    detail = helper.lead_table_conversion(lead, { channel_label: "Meta Ads", icon: "bi-meta", color: "blue" })
    expect(detail).to include(label: "Formulário: Apartamentos Barra Sul", campaign: "Lançamento", icon: "ui-checks")
  end

  it "mantém conversão no site para tráfego Meta sem formulário nativo" do
    lead = build(:lead, product: "Apartamento", other_information: {})
    detail = helper.lead_table_conversion(lead, {
      channel_label: "Meta Ads", conversion_origin_label: "Site", campaign: "Campanha UTM"
    })
    expect(detail).to include(label: "Conversão: Site", campaign: "Campanha UTM", icon: "globe2")
  end

  it "não inventa formulário nem campanha para origem não informada" do
    detail = helper.lead_table_conversion(build(:lead, other_information: {}), {
      channel_label: "Origem não informada", icon: "bi-inbox", color: "gray"
    })
    expect(detail).to include(label: "Canal: Origem não informada", campaign: nil)
  end
end
