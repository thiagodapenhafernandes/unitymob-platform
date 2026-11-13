require "rails_helper"

RSpec.describe ExternalLeadMigration::ExportLeadJob do
  let(:tenant) { Tenant.default }
  let(:client) { instance_double(ExternalLeadMigration::Client) }
  let(:integration) { create(:external_lead_integration, tenant:, export_enabled: true) }

  before do
    integration
    allow(ExternalLeadMigration::Client).to receive(:new).with(token: integration.access_token).and_return(client)
  end

  it "não executa um segundo envio enquanto outro worker exporta o mesmo lead" do
    lead = create(:lead, tenant: tenant)
    allow(client).to receive(:create_lead)
    config = Lead.connection_db_config.configuration_hash
    connection = PG.connect(dbname: config[:database], user: config[:username], password: config[:password], host: config[:host], port: config[:port])
    connection.exec("SELECT pg_advisory_lock(#{described_class::EXPORT_LOCK_NAMESPACE}, #{lead.id})")
    described_class.perform_now(lead.id, tenant_id: tenant.id)
    expect(client).not_to have_received(:create_lead)
  ensure
    connection&.close
  end

  it "envia por uma regra C2S mesmo com exportação global desligada" do
    integration.update!(export_enabled: false)
    rule = create(:distribution_rule, tenant: tenant, delivery_destination: "c2s")
    lead = create(:lead, tenant: tenant, distribution_rule: rule, skip_automatic_routing: true)
    allow(client).to receive(:create_lead).and_return("success" => true, "lead_id" => "scoped-1")
    described_class.perform_now(lead.id, tenant_id: tenant.id)
    described_class.perform_now(lead.id, tenant_id: tenant.id)
    expect(client).to have_received(:create_lead).once
    expect(lead.reload.c2s_export_external_id).to eq("scoped-1")
  end

  it "cancela envio pendente se a regra C2S for desativada" do
    integration.update!(export_enabled: false)
    rule = create(:distribution_rule, tenant: tenant, delivery_destination: "c2s")
    lead = create(:lead, tenant: tenant, distribution_rule: rule, skip_automatic_routing: true)
    rule.update!(active: false)
    allow(client).to receive(:create_lead)
    described_class.perform_now(lead.id, tenant_id: tenant.id)
    expect(client).not_to have_received(:create_lead)
  end

  it "registra a indisponibilidade e tenta novamente sem atribuir corretor local" do
    integration.update!(export_enabled: false)
    rule = create(:distribution_rule, tenant: tenant, delivery_destination: "c2s")
    lead = create(:lead, tenant: tenant, distribution_rule: rule, skip_automatic_routing: true)
    integration.update!(status: "disconnected")
    expect { described_class.perform_now(lead.id, tenant_id: tenant.id) }.to have_enqueued_job(described_class)
    expect(lead.reload.admin_user_id).to be_nil
    expect(lead.c2s_exported_at).to be_nil
    expect(lead.activities.where(kind: "external_lead_export_failed")).to exist
  end

  it "não marca como enviado se o C2S não confirmar um ID" do
    lead = create(:lead, tenant: tenant)
    allow(client).to receive(:create_lead).and_return("success" => true)
    expect { described_class.perform_now(lead.id, tenant_id: tenant.id) }.to raise_error(described_class::InvalidResponse)
    expect(lead.reload.c2s_exported_at).to be_nil
    expect(lead.activities.where(kind: "external_lead_export_failed")).to exist
  end

  it "não acessa um lead de outra conta" do
    foreign = Tenant.create!(name: "Outra", slug: "c2s-job-#{SecureRandom.hex(3)}")
    lead = create(:lead, tenant: foreign)
    allow(client).to receive(:create_lead)
    described_class.perform_now(lead.id, tenant_id: tenant.id)
    expect(client).not_to have_received(:create_lead)
  end

  it "não exporta contato administrativo, mas agenda a exportação ao virar lead comercial" do
    allow(client).to receive(:create_lead)
    contact = nil
    expect {
      contact = create(:lead, tenant: tenant, origin: "whatsapp", skip_automatic_routing: true,
        other_information: { "whatsapp_service_contact" => true })
    }.not_to have_enqueued_job(described_class)

    described_class.perform_now(contact.id, tenant_id: tenant.id)
    expect(client).not_to have_received(:create_lead)
    expect { contact.promote_whatsapp_contact! }.to have_enqueued_job(described_class).with(contact.id, tenant_id: tenant.id)
  end

  it "envia lead novo, marca como exportado e registra atividade" do
    lead = create(:lead, tenant:, origin: "Site")
    allow(client).to receive(:create_lead).and_return({ "success" => true, "lead_id" => "c2s-123" })

    expect { described_class.perform_now(lead.id, tenant_id: tenant.id) }
      .to change { integration.reload.exported_count }.by(1)

    lead.reload
    expect(lead.c2s_export_external_id).to eq("c2s-123")
    expect(lead.c2s_exported_at).to be_present
    expect(client).to have_received(:create_lead).with(hash_including("data" => hash_including("attributes" => hash_including("name" => lead.display_name))), path: "/leads")
    expect(lead.activities.where(kind: "external_lead_exported")).to exist
    expect(integration.last_exported_at).to be_present
    expect(integration.last_export_error).to be_nil
  end

  it "usa o endpoint configurado na integração" do
    integration.update!(export_endpoint: "/api/v2/leads/import")
    lead = create(:lead, tenant:, origin: "Site")
    allow(client).to receive(:create_lead).and_return({ "id" => "c2s-9" })

    described_class.perform_now(lead.id, tenant_id: tenant.id)

    expect(client).to have_received(:create_lead).with(anything, path: "/api/v2/leads/import")
  end

  it "não reenvia lead já exportado" do
    lead = create(:lead, tenant:, origin: "Site", c2s_export_external_id: "c2s-1", c2s_exported_at: 1.hour.ago)
    allow(client).to receive(:create_lead)

    described_class.perform_now(lead.id, tenant_id: tenant.id)

    expect(client).not_to have_received(:create_lead)
  end

  it "não envia quando a exportação está desligada ou desconectada" do
    lead = create(:lead, tenant:, origin: "Site")
    allow(client).to receive(:create_lead)

    integration.update!(export_enabled: false)
    described_class.perform_now(lead.id, tenant_id: tenant.id)
    integration.update!(export_enabled: true, status: "disconnected")
    described_class.perform_now(lead.id, tenant_id: tenant.id)

    expect(client).not_to have_received(:create_lead)
  end

  it "nunca exporta leads vindos do próprio C2S" do
    imported = create(:lead, tenant:, origin: ExternalLeadIntegration::LEAD_ORIGIN,
      external_lead_integration: integration, external_lead_id: "c2s-orig")
    tagged = create(:lead, tenant:, origin: "Site",
      other_information: { "webhook_tags" => [ExternalLeadIntegration::WEBHOOK_TAG] })
    allow(client).to receive(:create_lead)

    described_class.perform_now(imported.id, tenant_id: tenant.id)
    described_class.perform_now(tagged.id, tenant_id: tenant.id)

    expect(client).not_to have_received(:create_lead)
  end

  it "registra falha e tenta de novo em erro transitório" do
    lead = create(:lead, tenant:, origin: "Site")
    allow(client).to receive(:create_lead).and_raise(ExternalLeadMigration::Client::Error, "HTTP 500")

    expect { described_class.perform_now(lead.id, tenant_id: tenant.id) }
      .to have_enqueued_job(described_class)

    expect(integration.reload.export_failed_count).to eq(1)
    expect(integration.last_export_error).to include("HTTP 500")
    expect(lead.reload.c2s_exported_at).to be_nil
  end

  it "registra falha de credencial sem retry" do
    lead = create(:lead, tenant:, origin: "Site")
    allow(client).to receive(:create_lead).and_raise(ExternalLeadMigration::Client::UnauthorizedError, "token inválido")

    expect { described_class.perform_now(lead.id, tenant_id: tenant.id) }.not_to raise_error

    expect(integration.reload.export_failed_count).to eq(1)
    expect(integration.last_export_error).to include("token inválido")
  end
end
