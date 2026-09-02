require "rails_helper"

RSpec.describe MetaLeadProcessingJob, type: :job do
  around do |example|
    Lead.skip_callback(:commit, :after, :route_lead)
    example.run
  ensure
    Lead.set_callback(:commit, :after, :route_lead)
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
          { "name" => "full_name", "values" => ["Maria Meta"] },
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
    expect(lead.phone).to eq("5547999990000")
    expect(lead.product).to eq("Captação Meta Tenant")
    expect(lead.other_information["meta_page_id"]).to eq("page-meta-tenant")
    expect(lead.other_information["meta_integration_user_id"]).to eq(admin.id)
  end

  it "adiciona formulario desconhecido em regra Meta e deixa o lead elegivel para distribuicao" do
    tenant = Tenant.create!(name: "Conta Meta Auto #{SecureRandom.hex(3)}", slug: "conta-meta-auto-#{SecureRandom.hex(3)}")
    admin = create(:admin_user, :admin, tenant: tenant)
    broker = create(:admin_user, :field_agent, tenant: tenant)
    integration = create(:user_meta_integration, admin_user: admin, tenant: tenant, access_token: "user-token")
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
