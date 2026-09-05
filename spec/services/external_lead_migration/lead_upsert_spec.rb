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
    expect(lead.lead_labels.pluck(:name)).to include("Landing Praia")
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

  it "preserva o corretor mapeado mesmo quando o lead externo esta descartado" do
    discarded_payload = payload.deep_dup
    discarded_payload["id"] = "lead-descartado-com-dono"
    discarded_payload["attributes"]["customer"]["id"] = "customer-descartado-com-dono"
    discarded_payload["attributes"]["lead_status"] = { "name" => "Descartado", "alias" => "archived" }
    discarded_payload["attributes"]["funnel_status"] = { "name" => "Descartado" }

    described_class.call(integration:, payload: discarded_payload, historical: true)

    lead = tenant.leads.find_by!(external_lead_id: "lead-descartado-com-dono")
    expect(lead.status).to eq("Descartado")
    expect(lead.admin_user).to eq(broker)
  end

  it "atribui leads do vendedor lixeira ao usuario local dedicado quando existir" do
    trash_user = create(:admin_user, tenant:, email: ExternalLeadIntegration::LEGACY_TRASH_LOCAL_EMAIL, name: "Lixeira Conexão BC")
    trash_payload = payload.deep_dup
    trash_payload["id"] = "lead-lixeira-com-dono"
    trash_payload["attributes"]["customer"]["id"] = "customer-lixeira-com-dono"
    trash_payload["attributes"]["seller"] = {
      "id" => "seller-trash",
      "name" => "Lixeira Conexão BC",
      "email" => "lixeira_cbc2025@c2sglobal.com"
    }

    described_class.call(integration:, payload: trash_payload, historical: true)

    lead = tenant.leads.find_by!(external_lead_id: "lead-lixeira-com-dono")
    expect(lead.admin_user).to eq(trash_user)
  end

  it "atribui pelo codigo externo do vendedor quando ele corresponde ao vista_id local" do
    broker.update!(vista_id: "108")
    external_id_payload = payload.deep_dup
    external_id_payload["id"] = "lead-c2s-vista-id"
    external_id_payload["attributes"]["customer"]["id"] = "customer-c2s-vista-id"
    external_id_payload["attributes"]["seller"] = {
      "id" => "seller-hash-c2s",
      "name" => "Adriana Stark",
      "email" => "adriana.stark@saluteimoveis.com",
      "external_id" => "108",
      "external_name" => "Adriana Stark"
    }
    external_id_integration = create(:external_lead_integration, tenant:, seller_mappings: {})

    described_class.call(integration: external_id_integration, payload: external_id_payload, historical: true)

    lead = tenant.leads.find_by!(external_lead_id: "lead-c2s-vista-id")
    expect(lead.admin_user).to eq(broker)
  end

  it "extrai o corpo da primeira mensagem quando o provedor envia a mensagem estruturada" do
    structured_payload = payload.deep_dup
    structured_payload["id"] = "lead-structured-first-message"
    structured_payload["attributes"]["customer"]["id"] = "customer-structured-message"
    structured_payload["first_message"] = {
      "id" => "d2239250bdea687875dfdf305942680d",
      "sender_id" => "94a35ac97dc4b9c77eefe9cdde02728b",
      "recipient_id" => "3e6d3f3db93323638185f413d13a89fa",
      "sender_type" => "Customer",
      "recipient_type" => "Seller",
      "body" => "\n Você está interessado em receber informações sobre imóveis à venda?: sim.\n Full name: Maria Elisabete Marchi Pereira\n Plataforma: Instagram Leads",
      "created_at" => "2026-08-12T08:14:04.000-03:00"
    }
    structured_payload["messages"] = []

    described_class.call(integration:, payload: structured_payload, historical: true)

    lead = tenant.leads.find_by!(external_lead_id: "lead-structured-first-message")
    expect(lead.notes).to include("Full name: Maria Elisabete Marchi Pereira")
    expect(lead.notes).to include("Plataforma: Instagram Leads")
    expect(lead.notes).not_to include('"sender_id"=>')

    activity = lead.activities.find_by!(kind: "external_first_message")
    expect(activity.metadata["body"]).to include("Full name: Maria Elisabete Marchi Pereira")
    expect(activity.metadata["body"]).not_to include('"sender_id"=>')
  end

  it "usa os campos de agendamento do C2S para criar tarefas e visitas na data correta" do
    c2s_payload = payload.deep_dup
    c2s_payload["id"] = "lead-c2s-schedule-fields"
    c2s_payload["attributes"]["customer"]["id"] = "customer-c2s-schedule"
    c2s_payload["attributes"]["customer"]["name"] = "Cliente Agenda C2S"
    c2s_payload["attributes"]["schedulated_actions"] = [
      {
        "id" => "schedule-return",
        "status" => "Em aberto",
        "created_at" => "2026-08-15T13:43:30.000-03:00",
        "schedulated_action_date" => "2026-08-20T09:00:00.000-03:00",
        "schedulated_action_name" => "Retornar para o cliente",
        "schedulated_action_type_alias" => "feedback_customer"
      },
      {
        "id" => "schedule-visit",
        "status" => "Em aberto",
        "created_at" => "2026-08-15T13:44:30.000-03:00",
        "schedulated_action_date" => "2026-08-21T15:30:00.000-03:00",
        "schedulated_action_name" => "Visita Agendada",
        "schedulated_action_type_alias" => "scheduled_visit"
      }
    ]

    described_class.call(integration:, payload: c2s_payload, historical: true)

    lead = tenant.leads.find_by!(external_lead_id: "lead-c2s-schedule-fields")
    task = lead.tasks.find_by!(title: "Retornar para o cliente")
    appointment = lead.appointments.find_by!(title: "Visita Agendada")

    expect(task).to have_attributes(
      admin_user: broker,
      kind: "follow_up",
      status: "pendente",
      due_at: Time.zone.parse("2026-08-20T09:00:00.000-03:00")
    )
    expect(appointment).to have_attributes(
      admin_user: broker,
      kind: "visita",
      status: "agendado",
      starts_at: Time.zone.parse("2026-08-21T15:30:00.000-03:00")
    )
  end

  it "nao atribui agenda C2S ao usuario conector quando o vendedor externo esta sem mapeamento" do
    connector = create(:admin_user, tenant:, email: "conector-c2s@example.test")
    unmapped_integration = create(
      :external_lead_integration,
      tenant:,
      connected_by_admin_user: connector,
      seller_mappings: {}
    )
    unmapped_payload = payload.deep_dup
    unmapped_payload["id"] = "lead-c2s-unmapped-seller"
    unmapped_payload["attributes"]["customer"]["id"] = "customer-c2s-unmapped-seller"
    unmapped_payload["attributes"]["seller"] = {
      "id" => "seller-sem-par",
      "name" => "Vendedor sem par",
      "email" => "sem-par-c2s@example.test"
    }

    described_class.call(integration: unmapped_integration, payload: unmapped_payload, historical: true)

    lead = tenant.leads.find_by!(external_lead_id: "lead-c2s-unmapped-seller")
    activity = lead.activities.find_by!(kind: "external_scheduled_action")

    expect(lead.admin_user).to be_nil
    expect(lead.tasks).to be_empty
    expect(activity.metadata).to include(
      "unassigned" => true,
      "unassigned_reason" => "external_seller_unmapped"
    )
  end

  it "usa a distribuicao local para agenda de novo lead C2S sem vendedor mapeado" do
    connector = create(:admin_user, tenant:, email: "conector-webhook-c2s@example.test")
    create(:distribution_rule_agent, tenant:, distribution_rule: rule, admin_user: broker)
    unmapped_integration = create(
      :external_lead_integration,
      tenant:,
      distribution_rule: rule,
      connected_by_admin_user: connector,
      seller_mappings: {}
    )
    webhook_payload = payload.deep_dup
    webhook_payload["id"] = "lead-c2s-webhook-unmapped-seller"
    webhook_payload["attributes"]["customer"]["id"] = "customer-c2s-webhook-unmapped-seller"
    webhook_payload["attributes"]["seller"] = {
      "id" => "seller-webhook-sem-par",
      "name" => "Vendedor webhook sem par",
      "email" => "webhook-sem-par-c2s@example.test"
    }

    described_class.call(integration: unmapped_integration, payload: webhook_payload, historical: false)

    lead = tenant.leads.find_by!(external_lead_id: "lead-c2s-webhook-unmapped-seller")
    task = lead.tasks.find_by!(title: "Retorno comercial")

    expect(lead.admin_user).to eq(broker)
    expect(task.admin_user).to eq(broker)
  end
end
