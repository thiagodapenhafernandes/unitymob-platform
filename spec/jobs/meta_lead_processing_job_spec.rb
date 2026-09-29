require "rails_helper"

RSpec.describe MetaLeadProcessingJob, type: :job do
  before { allow_any_instance_of(Lead).to receive(:route_lead) }

  def create_meta_setup(tenant, page_id:)
    admin = create(:admin_user, :admin, tenant: tenant)
    integration = create(:user_meta_integration, admin_user: admin, tenant: tenant, access_token: "user-token")
    create(:meta_facebook_page, user_meta_integration: integration, page_id: page_id, access_token: "page-token")
  end

  def process_meta_lead(leadgen_id, page_id, form_id, field_data)
    service = instance_double(
      Facebook::MetaService,
      get_lead_details: { "id" => leadgen_id, "field_data" => field_data }
    )
    allow(Facebook::MetaService).to receive(:new).and_return(service)
    described_class.perform_now(leadgen_id, page_id, form_id)
  end

  it "identifica empreendimento pelo nome sem escolher uma unidade ou outra conta" do
    property = create(:habitation, tipo: "Empreendimento", nome_empreendimento: "Gralha Azul Condomínio Residencial", status: "Venda", exibir_no_site_flag: true)
    tenant = property.tenant
    unit = create(:habitation, tenant: tenant, nome_empreendimento: property.nome_empreendimento, status: "Venda", exibir_no_site_flag: true)
    expect(described_class.property_from_text(tenant, "Form - Gralha Azul 1M")).to eq(property)
    expect(described_class.property_from_text(tenant, "Form - Gralha Azul 1M CÓD 999999999")).to be_nil
    expect(described_class.property_from_text(tenant, "CÓD 2788 E 2940 Gralha Azul")).to be_nil
    other = Tenant.create!(name: "Outra conta nomes", slug: "other-property-names")
    expect(described_class.property_from_text(other, "Form - Gralha Azul 1M")).to be_nil
    create(:habitation, tenant: tenant, tipo: "Empreendimento", nome_empreendimento: property.nome_empreendimento, status: "Venda", exibir_no_site_flag: true)
    expect(described_class.property_from_text(tenant, "Form - Gralha Azul 1M")).to be_nil
  end

  it "cria o lead no tenant do usuario dono da integracao Meta" do
    tenant = Tenant.create!(name: "Conta Meta #{SecureRandom.hex(3)}", slug: "conta-meta-#{SecureRandom.hex(3)}")
    admin = create(:admin_user, :admin, tenant: tenant)
    integration = create(:user_meta_integration, admin_user: admin, access_token: "user-token")
    page = create(:meta_facebook_page, user_meta_integration: integration, page_id: "page-meta-tenant", access_token: "page-token")
    create(:meta_lead_form, meta_facebook_page: page, form_id: "form-meta-tenant", name: "Captação Meta Tenant")
    create(:meta_lead_form, form_id: "form-meta-outro", name: "Formulário de outra integração")
    service = instance_double(
      Facebook::MetaService,
      get_lead_details: {
        "id" => "lead-meta-1",
        "field_data" => [
          { "name" => "nome_completo", "values" => ["Maria Meta"] },
          { "name" => "email", "values" => ["maria@example.com"] },
          { "name" => "phone_number", "values" => ["5547999990000"] }
        ]
      }
    )

    allow(Facebook::MetaService).to receive(:new).with("page-token").and_return(service)

    expect {
      described_class.perform_now("lead-meta-1", "page-meta-tenant", "form-meta-tenant")
    }.to change { tenant.leads.count }.by(1)

    lead = tenant.leads.last
    expect(lead.admin_user).to be_nil
    expect(lead.name).to eq("Maria Meta")
    expect(lead.client_name).to eq("Maria Meta")
    expect(lead.phone).to eq("5547999990000")
    expect(lead.product).to eq("Captação Meta Tenant")
    expect(lead.attribution_channel).to eq("meta_ads")
    expect(lead.attribution_source).to eq("meta")
    expect(lead.attribution_data).to include(
      "provider" => "facebook_lead_ads",
      "page_id" => "page-meta-tenant",
      "form_id" => "form-meta-tenant"
    )
    expect(lead.other_information["meta_page_id"]).to eq("page-meta-tenant")
    expect(lead.other_information["meta_integration_user_id"]).to eq(admin.id)
  end

  it "vincula o imovel de interesse quando o nome do formulario Meta informa o codigo" do
    tenant = Tenant.create!(name: "Conta Meta Imovel #{SecureRandom.hex(3)}", slug: "conta-meta-imovel-#{SecureRandom.hex(3)}")
    property = create(:habitation, tenant: tenant, codigo: "3168", status: "Venda", exibir_no_site_flag: true)
    admin = create(:admin_user, :admin, tenant: tenant)
    integration = create(:user_meta_integration, admin_user: admin, access_token: "user-token")
    page = create(:meta_facebook_page, user_meta_integration: integration, page_id: "page-meta-property", access_token: "page-token")
    create(:meta_lead_form, meta_facebook_page: page, form_id: "form-meta-property", name: "Form Petrópolis - CÓD: 3168")
    service = instance_double(
      Facebook::MetaService,
      get_lead_details: {
        "id" => "lead-meta-property",
        "field_data" => [
          { "name" => "full_name", "values" => ["Olavo Orso"] },
          { "name" => "email", "values" => ["olavo@example.com"] },
          { "name" => "phone_number", "values" => ["5545999740757"] }
        ]
      }
    )

    allow(Facebook::MetaService).to receive(:new).with("page-token").and_return(service)

    described_class.perform_now("lead-meta-property", "page-meta-property", "form-meta-property")

    lead = tenant.leads.where("other_information->>'meta_leadgen_id' = ?", "lead-meta-property").first!
    expect(lead.property_id).to eq(property.id)
    expect(lead.property_interests.pluck(:habitation_id)).to contain_exactly(property.id)
    expect(lead.other_information["meta_property_code"]).to eq("3168")
  end

  it "nao vincula imovel quando o nome do formulario Meta tem mais de um codigo" do
    tenant = Tenant.create!(name: "Conta Meta Ambigua #{SecureRandom.hex(3)}", slug: "conta-meta-ambigua-#{SecureRandom.hex(3)}")
    create(:habitation, tenant: tenant, codigo: "2788", status: "Venda", exibir_no_site_flag: true)
    admin = create(:admin_user, :admin, tenant: tenant)
    integration = create(:user_meta_integration, admin_user: admin, access_token: "user-token")
    page = create(:meta_facebook_page, user_meta_integration: integration, page_id: "page-meta-ambiguous", access_token: "page-token")
    create(:meta_lead_form, meta_facebook_page: page, form_id: "form-meta-ambiguous", name: "CÓD 2788 E 2940")
    service = instance_double(
      Facebook::MetaService,
      get_lead_details: {
        "id" => "lead-meta-ambiguous",
        "field_data" => [
          { "name" => "full_name", "values" => ["Cliente Ambiguo"] },
          { "name" => "phone_number", "values" => ["5547999990000"] }
        ]
      }
    )

    allow(Facebook::MetaService).to receive(:new).with("page-token").and_return(service)

    described_class.perform_now("lead-meta-ambiguous", "page-meta-ambiguous", "form-meta-ambiguous")

    lead = tenant.leads.where("other_information->>'meta_leadgen_id' = ?", "lead-meta-ambiguous").first!
    expect(lead.property_id).to be_nil
    expect(lead.property_interests).to be_empty
  end

  it "cria o lead mesmo quando a resolucao de imovel falha" do
    tenant = Tenant.create!(name: "Conta Meta Sem Bloqueio #{SecureRandom.hex(3)}", slug: "conta-meta-sem-bloqueio-#{SecureRandom.hex(3)}")
    admin = create(:admin_user, :admin, tenant: tenant)
    integration = create(:user_meta_integration, admin_user: admin, access_token: "user-token")
    page = create(:meta_facebook_page, user_meta_integration: integration, page_id: "page-meta-safe", access_token: "page-token")
    create(:meta_lead_form, meta_facebook_page: page, form_id: "form-meta-safe", name: "Form Petrópolis - CÓD: 3168")
    service = instance_double(
      Facebook::MetaService,
      get_lead_details: {
        "id" => "lead-meta-safe",
        "field_data" => [
          { "name" => "full_name", "values" => ["Cliente Seguro"] },
          { "name" => "phone_number", "values" => ["5547999990000"] }
        ]
      }
    )

    allow(Facebook::MetaService).to receive(:new).with("page-token").and_return(service)
    allow(described_class).to receive(:property_from_text).and_raise(ActiveRecord::StatementInvalid, "falha de lookup")

    expect {
      described_class.perform_now("lead-meta-safe", "page-meta-safe", "form-meta-safe")
    }.to change { tenant.leads.count }.by(1)

    lead = tenant.leads.where("other_information->>'meta_leadgen_id' = ?", "lead-meta-safe").first!
    expect(lead.property_id).to be_nil
  end

  it "adiciona formulario desconhecido em regra Meta e deixa o lead elegivel para distribuicao" do
    tenant = Tenant.create!(name: "Conta Meta Auto #{SecureRandom.hex(3)}", slug: "conta-meta-auto-#{SecureRandom.hex(3)}")
    admin = create(:admin_user, :admin, tenant: tenant)
    broker = create(:admin_user, :field_agent, tenant: tenant)
    integration = create(:user_meta_integration, admin_user: admin, tenant: tenant, access_token: "user-token", selected_page_ids: ["page-auto"])
    create(:meta_facebook_page, user_meta_integration: integration, page_id: "page-auto", access_token: "page-token")
    rule = create(
      :distribution_rule,
      tenant: tenant,
      source_meta: true,
      source_site: false,
      auto_add_forms: true,
      meta_page_ids: ["page-auto"],
      meta_forms: []
    )
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: broker)
    service = instance_double(
      Facebook::MetaService,
      get_lead_details: {
        "id" => "lead-meta-auto",
        "field_data" => [
          { "name" => "full_name", "values" => ["Maria Meta"] },
          { "name" => "email", "values" => ["maria@example.com"] },
          { "name" => "phone_number", "values" => ["5547999990000"] }
        ]
      }
    )

    allow(Facebook::MetaService).to receive(:new).with("page-token").and_return(service)

    described_class.perform_now("lead-meta-auto", "page-auto", "form-new-auto")

    expect(rule.reload.meta_forms).to include("form-new-auto")
    lead = tenant.leads.last
    Current.set(tenant: tenant) { Leads::DistributorService.find_and_distribute(lead) }
    expect(lead.reload.distribution_rule_id).to eq(rule.id)
    expect(lead.admin_user_id).to eq(broker.id)
    expect(MetaLeadForm.find_by(form_id: "form-new-auto")).to be_present
  end

  it "reconhece nomes em portugues, ingles e perguntas personalizadas" do
    ["nome", "name", "nome_completo", "full_name", "fullname", "fullName", "nomeCompleto",
     "NÓME-COMPLETO", "Qual é o seu nome completo?", "informe_seu_nome", "your name"].each do |label|
      attributes = described_class.new.send(:extract_lead_attributes, {
        "field_data" => [{"name" => label, "values" => ["  Alissia P B Montibeller  "]}]
      })
      expect(attributes[:name]).to eq("Alissia P B Montibeller"), label
    end
  end

  it "prioriza nome completo mesmo depois de primeiro nome ou de campos vazios" do
    fields = [{"name" => "first_name", "values" => ["Maria"]},
              {"name" => "full_name", "values" => [" "]},
              {"name" => "nome_completo", "values" => ["Maria da Silva"]},
              {"name" => "last_name", "values" => ["Silva"]}]
    expect(described_class.new.send(:extract_lead_attributes, {"field_data" => fields})[:name]).to eq("Maria da Silva")
  end

  it "junta primeiro nome e sobrenome independentemente da ordem sem duplicar sobrenome" do
    [["first_name", "last_name"], ["primeiro_nome", "sobrenome"], ["nome", "surname"]].each do |first, last|
      fields = [{"name" => last, "values" => ["Silva"]}, {"name" => first, "values" => ["Maria"]}]
      expect(described_class.new.send(:extract_lead_attributes, {"field_data" => fields})[:name]).to eq("Maria Silva")
      fields.last["values"] = ["Maria Silva"]
      expect(described_class.new.send(:extract_lead_attributes, {"field_data" => fields})[:name]).to eq("Maria Silva")
    end
  end

  it "nao usa nome de campanha, empreendimento, username ou sobrenome isolado como pessoa" do
    fields = %w[campaign_name nome_do_empreendimento nome_da_campanha company_name username sobrenome].map do |label|
      {"name" => label, "values" => ["Nao e o nome"]}
    end
    expect(described_class.new.send(:extract_lead_attributes, {"field_data" => fields})[:name]).to eq("Lead Facebook")
    fields.pop
    fields << {"name" => "nome", "values" => ["Alissia"]}
    expect(described_class.new.send(:extract_lead_attributes, {"field_data" => fields})[:name]).to eq("Alissia")
  end

  it "extrai telefone de campos Meta com abreviacoes brasileiras" do
    attributes = described_class.new.send(:extract_lead_attributes, {
      "field_data" => [
        { "name" => "full_name", "values" => ["Cliente Teste"] },
        { "name" => "email", "values" => ["cliente@example.com"] },
        { "name" => "confirme_seu_wpp!", "values" => ["21990872427"] }
      ]
    })

    expect(attributes[:phone]).to eq("21990872427")
  end

  it "ignora campo de whatsapp com texto livre e usa phone_number oficial" do
    attributes = described_class.new.send(:extract_lead_attributes, {
      "field_data" => [
        { "name" => "confirme_seu_whatsapp;", "values" => ["Jesus Cristo"] },
        { "name" => "full_name", "values" => ["Vinicius_Lima"] },
        { "name" => "phone_number", "values" => ["+554791456154"] },
        { "name" => "email", "values" => ["viniciuslimaalz9@gmail.com"] }
      ]
    })

    expect(attributes[:phone]).to eq("+554791456154")
  end

  it "usa fallback por valor quando o campo de telefone vem com rotulo nao padronizado" do
    attributes = described_class.new.send(:extract_lead_attributes, {
      "field_data" => [
        { "name" => "full_name", "values" => ["Cliente Teste"] },
        { "name" => "contato_preferencial", "values" => ["+55 21 99087-2427"] }
      ]
    })

    expect(attributes[:phone]).to eq("+55 21 99087-2427")
  end

  it "aceita numero local quando o campo indica telefone" do
    attributes = described_class.new.send(:extract_lead_attributes, {
      "field_data" => [
        { "name" => "full_name", "values" => ["Cliente Teste"] },
        { "name" => "telefone_para_contato", "values" => ["990872427"] }
      ]
    })

    expect(attributes[:phone]).to eq("990872427")
  end

  it "ignora reprocessamento do mesmo leadgen_id Meta" do
    tenant = Tenant.create!(name: "Conta Meta Dedupe #{SecureRandom.hex(3)}", slug: "conta-meta-dedupe-#{SecureRandom.hex(3)}")
    create_meta_setup(tenant, page_id: "page-meta-dedupe")
    fields = [
      { "name" => "full_name", "values" => ["Cliente Duplo"] },
      { "name" => "phone_number", "values" => ["5547999990001"] }
    ]

    expect {
      process_meta_lead("lead-meta-duplo", "page-meta-dedupe", "form-meta-duplo", fields)
    }.to change { tenant.leads.count }.by(1)

    expect {
      process_meta_lead("lead-meta-duplo", "page-meta-dedupe", "form-meta-duplo", fields)
    }.not_to change { tenant.leads.count }
  end

  it "ignora leadgen_id guardado nas chaves aninhadas da migração C2S" do
    tenant = Tenant.create!(name: "Conta Meta C2S #{SecureRandom.hex(3)}", slug: "conta-meta-c2s-#{SecureRandom.hex(3)}")
    create_meta_setup(tenant, page_id: "page-meta-c2s")
    variants = [
      [{ "facebook_attributes" => { "leadgen_id" => "lead-c2s-1", "form_id" => "form-c2s" } }, {}],
      [{ "external_lead_payload" => { "facebook_attributes" => { "leadgen_id" => "lead-c2s-2", "form_id" => "form-c2s" } } }, {}],
      [{ "data" => { "facebook_attributes" => { "leadgen_id" => "lead-c2s-3", "form_id" => "form-c2s" } } }, {}],
      [{}, { "facebook" => { "leadgen_id" => "lead-c2s-4", "form_id" => "form-c2s" } }]
    ]

    variants.each_with_index do |(other_information, attribution_data), index|
      # Telefone diferente do webhook: quem barra é o leadgen_id, não o fallback.
      create(
        :lead,
        tenant: tenant,
        phone: "554791111000#{index}",
        origin: "Migração externa",
        other_information: other_information,
        attribution_data: attribution_data
      )
      leadgen_id = "lead-c2s-#{index + 1}"
      fields = [
        { "name" => "full_name", "values" => ["Cliente C2S #{index}"] },
        { "name" => "phone_number", "values" => ["554792222000#{index}"] }
      ]

      expect {
        process_meta_lead(leadgen_id, "page-meta-c2s", "form-c2s", fields)
      }.not_to change { tenant.leads.count }, "variante #{index}"
    end
  end

  it "ignora reentrega tardia pelo fallback telefone + formulário" do
    tenant = Tenant.create!(name: "Conta Meta Fallback #{SecureRandom.hex(3)}", slug: "conta-meta-fallback-#{SecureRandom.hex(3)}")
    create_meta_setup(tenant, page_id: "page-meta-fallback")
    create(
      :lead,
      tenant: tenant,
      phone: "5547999990002",
      origin: "Migração externa",
      other_information: { "facebook_attributes" => { "leadgen_id" => "lead-antigo", "form_id" => "form-c2s-fallback" } },
      attribution_data: {}
    )
    fields = [
      { "name" => "full_name", "values" => ["Cliente Fallback"] },
      { "name" => "phone_number", "values" => ["+55 (47) 99999-0002"] }
    ]

    expect {
      process_meta_lead("lead-novo-outro-id", "page-meta-fallback", "form-c2s-fallback", fields)
    }.not_to change { tenant.leads.count }
  end

  it "cria o lead quando o telefone coincide mas o formulário é outro" do
    tenant = Tenant.create!(name: "Conta Meta Outro Form #{SecureRandom.hex(3)}", slug: "conta-meta-outro-form-#{SecureRandom.hex(3)}")
    create_meta_setup(tenant, page_id: "page-meta-outro-form")
    create(
      :lead,
      tenant: tenant,
      phone: "5547999990003",
      origin: "Migração externa",
      other_information: { "facebook_attributes" => { "leadgen_id" => "lead-antigo", "form_id" => "form-antigo" } },
      attribution_data: {}
    )
    fields = [
      { "name" => "full_name", "values" => ["Cliente Outro Form"] },
      { "name" => "phone_number", "values" => ["5547999990003"] }
    ]

    expect {
      process_meta_lead("lead-novo-form", "page-meta-outro-form", "form-novo", fields)
    }.to change { tenant.leads.count }.by(1)
  end

  it "restringe o dedupe ao tenant da integração" do
    tenant_a = Tenant.create!(name: "Conta Meta A #{SecureRandom.hex(3)}", slug: "conta-meta-a-#{SecureRandom.hex(3)}")
    tenant_b = Tenant.create!(name: "Conta Meta B #{SecureRandom.hex(3)}", slug: "conta-meta-b-#{SecureRandom.hex(3)}")
    create_meta_setup(tenant_a, page_id: "page-meta-shared")
    create_meta_setup(tenant_b, page_id: "page-meta-shared")
    create(
      :lead,
      tenant: tenant_b,
      phone: "5547999990004",
      origin: "Facebook Lead Ads",
      other_information: { "meta_leadgen_id" => "lead-shared", "meta_form_id" => "form-shared" },
      attribution_data: {}
    )
    fields = [
      { "name" => "full_name", "values" => ["Cliente Compartilhado"] },
      { "name" => "phone_number", "values" => ["5547999990004"] }
    ]

    expect {
      process_meta_lead("lead-shared", "page-meta-shared", "form-shared", fields)
    }.to change { tenant_a.leads.count }.by(1)

    expect(tenant_b.leads.count).to eq(1)
  end

  it "registra payload bruto quando o lead da Meta nao pode ser salvo" do
    tenant = Tenant.create!(name: "Conta Meta Falha #{SecureRandom.hex(3)}", slug: "conta-meta-falha-#{SecureRandom.hex(3)}")
    admin = create(:admin_user, :admin, tenant: tenant)
    integration = create(:user_meta_integration, admin_user: admin, tenant: tenant, access_token: "user-token")
    create(:meta_facebook_page, user_meta_integration: integration, page_id: "page-fail", access_token: "page-token")
    service = instance_double(
      Facebook::MetaService,
      get_lead_details: {
        "id" => "lead-meta-sem-phone",
        "field_data" => [
          { "name" => "full_name", "values" => ["Cliente Sem Telefone"] },
          { "name" => "email", "values" => ["cliente@example.com"] }
        ]
      }
    )

    allow(Facebook::MetaService).to receive(:new).with("page-token").and_return(service)
    allow(ErrorEvent).to receive(:record!)

    expect {
      described_class.perform_now("lead-meta-sem-phone", "page-fail", "form-fail")
    }.not_to change { tenant.leads.count }

    expect(ErrorEvent).to have_received(:record!).with(
      instance_of(ActiveRecord::RecordInvalid),
      hash_including(
        source: "job",
        severity: "warning",
        context: hash_including(
          source: "meta_lead_processing",
          tenant_id: tenant.id,
          meta_leadgen_id: "lead-meta-sem-phone",
          meta_page_id: "page-fail",
          meta_form_id: "form-fail",
          field_data: array_including(hash_including("name" => "email"))
        )
      )
    )
  end
end
