require "rails_helper"

RSpec.describe ExternalLeadMigration::LeadUpsert do
  let(:tenant) { Tenant.default }
  let(:broker) { create(:admin_user, tenant:, email: "corretor-externo@example.test", name: "Corretor Externo") }
  let(:rule) { create(:distribution_rule, tenant:, source_site: false, source_webhook: true, webhook_tags: [ExternalLeadIntegration::WEBHOOK_TAG]) }
  let(:habitation) { create(:habitation, tenant:, codigo: "AP-5533") }
  let(:integration) do
    create(
      :external_lead_integration,
      tenant:,
      distribution_rule: rule,
      seller_mappings: { "seller-1" => broker.id }
    )
  end

  let(:payload) do
    {
      "id" => "lead-lead-migration-1",
      "internal_id" => 5533,
      "attributes" => {
        "description" => "Apartamento frente mar",
        "url" => "https://legacy.example.test/leads/lead-lead-migration-1",
        "created_at" => "2026-08-01T12:00:00Z",
        "updated_at" => "2026-08-02T12:00:00Z",
        "funnel_status" => { "name" => "Visita agendada" },
        "lead_status" => { "name" => "Em atendimento", "alias" => "under_negotiation" },
        "lead_source" => { "name" => "Portal parceiro" },
        "channel" => { "name" => "Landing Page" },
        "facebook_attributes" => { "leadgen_id" => "fb-123", "form_id" => "form-1" },
        "customer" => {
          "id" => "customer-1",
          "name" => "Maria Externa",
          "email" => "maria@example.test",
          "phone" => "+55 47 99999-0000"
        },
        "seller" => {
          "id" => "seller-1",
          "name" => "Corretor Externo",
          "email" => "corretor-externo@example.test"
        },
        "product" => {
          "description" => "Apartamento frente mar",
          "prop_ref" => habitation.codigo,
          "city" => "Balneário Camboriú",
          "neighbourhood" => "Centro",
          "price_float" => 950000.0
        },
        "tags" => [{ "name" => "Landing Praia" }],
        "schedulated_actions" => [
          {
            "id" => "schedule-1",
            "name" => "Retorno comercial",
            "status" => "Em aberto",
            "due_at" => "2026-08-03T15:00:00Z",
            "description" => "Ligar para confirmar interesse"
          }
        ],
        "log" => [
          {
            "id" => "log-1",
            "title" => "Status alterado",
            "created_at" => "2026-08-02T13:00:00Z"
          }
        ]
      },
      "first_message" => "Tenho interesse no imóvel.",
      "messages" => [
        { "id" => "message-1", "body" => "Pode enviar detalhes?", "direction" => "in", "created_at" => "2026-08-01T12:03:00Z" }
      ],
      "custom_attributes" => [
        { "name" => "Objetivo", "value" => "Comprar" }
      ]
    }
  end

  before { Current.tenant = tenant }

  it "cria o lead no tenant usando o funil local replicado da origem externa" do
    expect {
      described_class.call(integration:, payload:, historical: true)
    }.to change(Lead, :count).by(1)
      .and change { tenant.lead_pipeline_stages.where(name: "Visita agendada").count }.by(1)

    lead = tenant.leads.find_by!(external_lead_id: "lead-lead-migration-1")
    expect(lead).to have_attributes(
      name: "Maria Externa",
      email: "maria@example.test",
      origin: ExternalLeadIntegration::LEAD_ORIGIN,
      lead_type: "webhook",
      status: "Visita agendada",
      external_internal_id: 5533,
      distribution_rule: rule,
      admin_user: broker,
      lead_pipeline: LeadPipeline.default_for(tenant: tenant),
      property_id: habitation.id,
      attribution_channel: "Landing Page",
      attribution_source: "Portal parceiro"
    )
    expect(lead.other_information["webhook_tags"]).to include(ExternalLeadIntegration::WEBHOOK_TAG, "landing praia")
    expect(lead.other_information["source"]).to eq("external_lead_migration")
    expect(lead.attribution_data.dig("facebook", "leadgen_id")).to eq("fb-123")
    expect(lead.custom_answers).to include("key" => "Objetivo", "answer" => "Comprar")
    expect(lead.property_interests.pluck(:habitation_id)).to contain_exactly(habitation.id)
    expect(lead.activities.pluck(:kind)).to include("external_first_message", "external_message", "external_log", "external_scheduled_action")
    expect(lead.tasks.where(title: "Retorno comercial", admin_user: broker, status: "pendente")).to exist
  end

  it "atualiza o mesmo lead externo sem duplicar o registro" do
    described_class.call(integration:, payload:, historical: true)

    updated_payload = payload.deep_dup
    updated_payload["attributes"]["customer"]["name"] = "Maria Atualizada"
    updated_payload["attributes"]["funnel_status"] = { "name" => "Proposta enviada" }

    expect {
      result = described_class.call(integration:, payload: updated_payload, historical: false)
      expect(result.action).to eq(:updated)
    }.not_to change(Lead, :count)

    lead = tenant.leads.find_by!(external_lead_id: "lead-lead-migration-1")
    expect(lead.name).to eq("Maria Atualizada")
    expect(lead.status).to eq("Proposta enviada")
    expect(lead.activities.where(kind: "external_message").count).to eq(1)
  end
end
