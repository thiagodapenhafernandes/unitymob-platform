require "rails_helper"

RSpec.describe ExternalLeadMigration::ReactivateLeadJob do
  let(:tenant) { Tenant.default }
  let(:admin) { create(:admin_user, :admin, tenant: tenant) }
  let!(:integration) { create(:external_lead_integration, tenant: tenant, export_enabled: false, mirror_c2s_owners: true) }
  let(:rule) { create(:distribution_rule, tenant: tenant, delivery_destination: "c2s", source_whatsapp_campaign: true) }
  let(:template) do
    WhatsappTemplate.create!(name: "reactivate_existing", status: "APPROVED", body: "Ainda está buscando?",
      buttons: { "0" => {"kind" => "quick_reply", "text" => "Estou buscando"}, "1" => {"kind" => "quick_reply", "text" => "Já aluguei"} })
  end
  let(:campaign) do
    WhatsappCampaign.create!(tenant: tenant, name: "Reativação", created_by: admin, whatsapp_template: template,
      response_decisions: {buttons: [{key: template.interactive_buttons.first["key"], action: "generate_lead", distribution_rule_id: rule.id},
        {key: template.interactive_buttons.second["key"], action: "ignore"}]})
  end
  let(:lead) do
    create(:lead, tenant: tenant, external_lead_integration: integration, external_lead_id: "existing-c2s-id",
      admin_user: admin, skip_automatic_routing: true, attribution_data: {"lead_source" => {"id" => 2049, "name" => "Disparo de WhatsApp"}}, other_information: {"historical_note" => "Preservar"})
  end
  let(:recipient) { campaign.campaign_recipients.create!(lead: lead, phone_number: lead.phone) }
  let(:message) do
    campaign.campaign_messages.create!(lead: lead, whatsapp_campaign_recipient: recipient, phone_number: lead.phone,
      status: "replied", replied_at: Time.current, reply_button_text: "Estou buscando", reply_button_payload: template.interactive_buttons.first["key"])
  end
  let(:operation) { C2sLeadReactivation.request!(lead: lead, campaign_message: message, distribution_rule: rule) }
  let(:client) { instance_double(ExternalLeadMigration::Client) }
  let(:remote) { {"data" => {"id" => "existing-c2s-id", "attributes" => {"lead_status" => {"id" => 3}, "log" => [{"body" => "Histórico preservado"}]}}} }
  let(:reactivated) { {"data" => {"id" => "existing-c2s-id", "attributes" => {"lead_status" => {"id" => 0}, "archive_details" => {"archived" => false}}}} }

  before do
    create(:lead, tenant: tenant, external_lead_integration: integration, external_lead_id: "source-reference",
      skip_automatic_routing: true, attribution_data: {"lead_source" => {"id" => 2049, "name" => "Disparo de WhatsApp"}})
    allow(ExternalLeadMigration::Client).to receive(:new).with(token: integration.access_token).and_return(client)
    allow(client).to receive(:lead).with("existing-c2s-id").and_return(remote)
    allow(client).to receive(:update_lead_routing) do
      remote["data"]["attributes"]["lead_source"] = {"name" => "Disparo de WhatsApp"}
      reactivated["data"]["attributes"]["lead_source"] = {"name" => "Disparo de WhatsApp"}
      remote["data"]["attributes"]["product"] = {"real_estate_detail" => {"negotiation_name" => "Aluguel"}}
      {"success" => true}
    end
    allow(client).to receive(:reactivate_lead).and_return(reactivated)
    allow(client).to receive(:redistribute_lead).and_return("success" => true, "seller_id" => "next-seller")
  end

  it "reativa e redistribui o mesmo ID, sem criar cadastro nem mudar a carteira local" do
    operation
    previous = lead.reload.attributes
    expect(client).not_to receive(:create_lead)
    expect { described_class.perform_now(operation.id, tenant_id: tenant.id) }.not_to change(Lead, :count)
    expect(client).to have_received(:update_lead_routing).with("existing-c2s-id", attributes: {"lead_source_id" => 2049}).once
    expect(client).to have_received(:reactivate_lead).with("existing-c2s-id", message: include("Interesse confirmado", "##{campaign.id}"))
    expect(client).to have_received(:redistribute_lead).with("existing-c2s-id").once
    expect(operation.reload).to have_attributes(status: "completed", seller_id: "next-seller", external_lead_id: "existing-c2s-id")
    expect(operation.reactivated_at).to be_present
    expect(operation.redistributed_at).to be_present
    expect(lead.reload.attributes).to eq(previous)
    expect(lead.activities.where(kind: "c2s_reactivation_completed")).to exist
  end

  it "envia a fonte e negociação configuradas na regra antes de redistribuir" do
    rule.update!(c2s_negotiation_type: "Aluguel", c2s_source: "Disparo de WhatsApp")
    described_class.perform_now(operation.id, tenant_id: tenant.id)
    expect(client).to have_received(:update_lead_routing).with("existing-c2s-id",
      attributes: {"lead_source_id" => 2049, "type_negotiation" => 1})
    expect(operation.reload.status).to eq("completed")
  end

  it "não redistribui quando o C2S ignora a atualização de origem" do
    allow(client).to receive(:update_lead_routing).and_return("success" => true)
    described_class.perform_now(operation.id, tenant_id: tenant.id)
    expect(operation.reload.status).to eq("failed")
    expect(operation.error_message).to include("Origem da campanha WhatsApp não confirmada")
    expect(client).not_to have_received(:reactivate_lead)
    expect(client).not_to have_received(:redistribute_lead)
  end

  it "não altera o cadastro quando a fonte configurada não tem identificação na conta" do
    rule.update!(c2s_source: "Fonte ainda não sincronizada")
    described_class.perform_now(operation.id, tenant_id: tenant.id)
    expect(client).not_to have_received(:update_lead_routing)
    expect(client).not_to have_received(:redistribute_lead)
    expect(operation.reload.status).to eq("failed")
  end

  it "não redistribui quando o C2S mantém a negociação anterior" do
    rule.update!(c2s_negotiation_type: "Compra")
    described_class.perform_now(operation.id, tenant_id: tenant.id)
    expect(operation.reload.status).to eq("failed")
    expect(operation.error_message).to include("Negociação da campanha não confirmada")
    expect(client).not_to have_received(:redistribute_lead)
  end

  it "ignora cliques e execuções repetidos para a mesma mensagem" do
    expect { 2.times { C2sLeadReactivation.request!(lead: lead, campaign_message: message, distribution_rule: rule) } }
      .to have_enqueued_job(described_class).once
    expect(tenant.c2s_lead_reactivations.count).to eq(1)
    existing = tenant.c2s_lead_reactivations.first
    2.times { described_class.perform_now(existing.id, tenant_id: tenant.id) }
    expect(client).to have_received(:reactivate_lead).once
    expect(client).to have_received(:redistribute_lead).once
  end

  it "retoma somente a redistribuição quando a reabertura já foi confirmada" do
    operation.update!(status: "reactivated", reactivated_at: Time.current)
    allow(client).to receive(:lead).and_return(reactivated)
    described_class.perform_now(operation.id, tenant_id: tenant.id)
    expect(client).not_to have_received(:reactivate_lead)
    expect(client).to have_received(:redistribute_lead).once
    expect(operation.reload.status).to eq("completed")
  end

  it "não gira a fila se o cadastro tiver mudado depois da reabertura" do
    operation.update!(status: "reactivated", reactivated_at: Time.current)
    described_class.perform_now(operation.id, tenant_id: tenant.id)
    expect(client).not_to have_received(:redistribute_lead)
    expect(operation.reload.status).to eq("failed")
  end

  it "bloqueia uma resposta que deixou de ser positiva antes da execução" do
    operation
    message.update!(reply_button_text: "Já aluguei", reply_button_payload: template.interactive_buttons.second["key"])
    described_class.perform_now(operation.id, tenant_id: tenant.id)
    expect(client).not_to have_received(:lead)
    expect(operation.reload.status).to eq("failed")
  end

  it "não altera o histórico quando a mensagem da campanha é excluída" do
    operation
    message.destroy!
    expect(operation.reload.whatsapp_campaign_message_id).to be_nil
    described_class.perform_now(operation.id, tenant_id: tenant.id)
    expect(operation.reload.status).to eq("failed")
    expect(client).not_to have_received(:lead)
  end

  it "também agenda pela decisão legada sem automação vinculada" do
    expect { message.mark_replied!(raw_payload: {id: "new-interest-click", type: "button", button: {text: "Estou buscando", payload: template.interactive_buttons.first["key"]}}) }
      .to have_enqueued_job(described_class)
    expect(tenant.c2s_lead_reactivations.count).to eq(1)
  end

  it "reutiliza também o ID de um lead anteriormente exportado pela Unitymob" do
    lead.update_columns(external_lead_integration_id: nil, external_lead_id: nil, c2s_export_external_id: "existing-c2s-id", c2s_exported_at: 1.day.ago)
    described_class.perform_now(operation.id, tenant_id: tenant.id)
    expect(operation.reload.status).to eq("completed")
    expect(client).to have_received(:redistribute_lead).with("existing-c2s-id").once
  end

  it "não aceita criar um lead local como efeito da solicitação de reativação" do
    expect { C2sLeadReactivation.request!(lead: build(:lead, tenant: tenant), campaign_message: message, distribution_rule: rule) }
      .to raise_error(ArgumentError, "Reativação exige um lead existente")
  end

  it "mantém a proteção para eventos automáticos que não sejam a resposta da campanha" do
    event = AutomationEvent.create!(tenant: tenant, lead: lead, name: "whatsapp_campaign_message_delivered", source: "whatsapp",
      payload: {whatsapp_campaign_message_id: message.id, whatsapp_campaign_recipient_id: recipient.id, whatsapp_campaign_id: campaign.id})
    executor = Automation::ActionExecutor.new(lead, automation_event: event)
    expect { executor.execute(type: "set_flow_result", result: "generates_attendance", distribution_rule_id: rule.id) }
      .not_to have_enqueued_job(described_class)
    expect(tenant.c2s_lead_reactivations).to be_empty
  end

  it "registra falha se a fila de jobs não aceitar o agendamento" do
    allow(described_class).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "indisponível")
    expect { operation }.to raise_error(ActiveJob::EnqueueError)
    request = tenant.c2s_lead_reactivations.first
    expect(request.status).to eq("failed")
    expect(lead.activities.where(kind: "c2s_reactivation_failed")).to exist
    expect(client).not_to have_received(:reactivate_lead)
  end

  it "registra falha quando o adapter retorna false sem lançar erro" do
    allow(described_class).to receive(:perform_later).and_return(false)
    expect { operation }.to raise_error(ActiveJob::EnqueueError)
    expect(tenant.c2s_lead_reactivations.first.status).to eq("failed")
    expect(lead.activities.where(kind: "c2s_reactivation_queued")).not_to exist
  end

  it "registra o status HTTP sem copiar dados sensíveis do erro do fornecedor" do
    allow(client).to receive(:lead).and_raise(ExternalLeadMigration::Client::Error.new("contato privado", http_status: 429))
    described_class.perform_now(operation.id, tenant_id: tenant.id)
    expect(operation.reload.status).to eq("failed")
    expect(operation.error_message).to include("HTTP 429")
    expect(operation.error_message).not_to include("contato privado")
    expect(client).not_to have_received(:reactivate_lead)
  end

  it "não trata falha de banco antes de carregar o pedido como sucesso" do
    tenant_id = tenant.id
    allow(Tenant).to receive(:find_by).with(id: tenant_id).and_raise(ActiveRecord::ConnectionNotEstablished)
    expect { described_class.new.perform(123, tenant_id: tenant_id) }.to raise_error(ActiveRecord::ConnectionNotEstablished)
  end

  it "não redistribui se a reabertura não confirmar o mesmo cadastro" do
    allow(client).to receive(:reactivate_lead).and_return("data" => {"id" => "different-id", "attributes" => {"lead_status" => {"id" => 0}}})
    described_class.perform_now(operation.id, tenant_id: tenant.id)
    expect(operation.reload.status).to eq("uncertain")
    expect(client).not_to have_received(:redistribute_lead)
  end

  it "não repete a redistribuição após timeout ambíguo" do
    allow(client).to receive(:redistribute_lead).and_raise(Net::ReadTimeout)
    2.times { described_class.perform_now(operation.id, tenant_id: tenant.id) }
    expect(operation.reload.status).to eq("uncertain")
    expect(operation.reactivated_at).to be_present
    expect(client).to have_received(:redistribute_lead).once
    expect(lead.activities.where(kind: "c2s_reactivation_uncertain")).to exist
  end

  it "não repete uma operação interrompida depois de iniciar uma chamada remota" do
    operation.update!(status: "redistributing", reactivated_at: Time.current)
    described_class.perform_now(operation.id, tenant_id: tenant.id)
    expect(operation.reload.status).to eq("uncertain")
    expect(client).not_to have_received(:lead)
    expect(client).not_to have_received(:redistribute_lead)
  end

  it "falha sem alterar o C2S se a conexão cair ou a fila for desligada" do
    operation
    integration.update!(enabled: false)
    described_class.perform_now(operation.id, tenant_id: tenant.id)
    expect(operation.reload.status).to eq("failed")
    expect(client).not_to have_received(:reactivate_lead)
  end

  it "não opera um pedido de outra conta" do
    operation
    other = Tenant.create!(name: "Outra", slug: "c2s-reactivate-#{SecureRandom.hex(4)}")
    described_class.perform_now(operation.id, tenant_id: other.id)
    expect(client).not_to have_received(:lead)
    expect(operation.reload.status).to eq("pending")
  end

  it "não reativa respostas negativas nem assume identidade de outra integração" do
    message.update!(reply_button_text: "Já aluguei", reply_button_payload: template.interactive_buttons.second["key"])
    expect { operation }.to raise_error(ArgumentError)
    expect(tenant.c2s_lead_reactivations).to be_empty
    message.update!(reply_button_text: "Estou buscando", reply_button_payload: template.interactive_buttons.first["key"])
    other = create(:external_lead_integration, tenant: Tenant.create!(name: "Outra", slug: "c2s-link-#{SecureRandom.hex(4)}"))
    lead.update_columns(external_lead_integration_id: other.id)
    expect { C2sLeadReactivation.request!(lead: lead, campaign_message: message, distribution_rule: rule) }.to raise_error(ArgumentError)
  end

  it "agenda o caminho explícito da automação mesmo com espelhamento e exportação global desligada" do
    event = AutomationEvent.create!(tenant: tenant, lead: lead, name: "whatsapp_campaign_message_replied", source: "whatsapp",
      payload: {whatsapp_campaign_message_id: message.id, whatsapp_campaign_recipient_id: recipient.id, whatsapp_campaign_id: campaign.id})
    executor = Automation::ActionExecutor.new(lead, automation_event: event)
    expect { executor.execute(type: "set_flow_result", result: "generates_attendance", distribution_rule_id: rule.id) }
      .to have_enqueued_job(described_class)
    expect(tenant.c2s_lead_reactivations.first.external_lead_id).to eq("existing-c2s-id")
    expect(lead.reload.admin_user_id).to eq(admin.id)
  end
end
