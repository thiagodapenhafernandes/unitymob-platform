require "rails_helper"

RSpec.describe Whatsapp::CampaignInteractionMetrics do
  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }
  let(:sender) { create(:whatsapp_sender_number, tenant: tenant) }
  let(:template) do
    tenant.whatsapp_templates.create!(name: "dynamic_metrics", language: "pt_BR", status: "APPROVED", body: "Escolha",
      buttons: {"0" => {"kind" => "quick_reply", "text" => "Visitar"}, "1" => {"kind" => "quick_reply", "text" => "Condições"}})
  end
  let(:campaign) do
    tenant.whatsapp_campaigns.create!(name: "Dinâmica", whatsapp_template: template, whatsapp_sender_number: sender,
      created_by: admin, status: "completed", total_recipients: 2, sent_count: 2, delivered_count: 2,
      response_decisions: {buttons: template.interactive_buttons.map { |b| b.merge("action" => "ignore") }})
  end
  let(:conversation) { tenant.whatsapp_conversations.create!(contact_phone: "5511999990000", whatsapp_sender_number: sender) }
  let(:message) { campaign.campaign_messages.create!(tenant: tenant, phone_number: conversation.contact_phone, status: "delivered", sent_at: Time.current, external_message_id: "outbound-1") }

  before { allow(Automation::Dispatcher).to receive(:dispatch) }

  def reply(label, id, target: message)
    inbound = conversation.messages.create!(tenant: tenant, direction: "inbound", wa_message_id: id,
      body: label.presence || "Quero saber mais", msg_type: label ? "button" : "text", context_wa_message_id: target.external_message_id)
    raw = {"id" => id, "type" => inbound.msg_type}
    raw["button"] = {"text" => label} if label
    target.mark_replied!(inbound_message: inbound, raw_payload: raw)
  end

  def metrics
    described_class.new(tenant: tenant, campaigns: tenant.whatsapp_campaigns.where(id: campaign.id))
  end

  it "preserva cliques repetidos, conta a pessoa uma vez por botão e não duplica o webhook" do
    first = reply("Visitar", "in-1")
    duplicate = message.mark_replied!(inbound_message: first.inbound_whatsapp_message, raw_payload: {"id" => "in-1", "type" => "button", "button" => {"text" => "Visitar"}})
    expect(duplicate.id).to eq(first.id)
    reply("Visitar", "in-2")
    reply("Condições", "in-3")
    expect(message.interactions.responses.count).to eq(3)
    expect(metrics.totals).to include(interactions: 1, clicks: 3)
    expect(metrics.button_cards(campaign).map { |card| [card[:label], card[:count], card[:clicks]] })
      .to contain_exactly(["Visitar", 1, 2], ["Condições", 1, 1])
    expect(Automation::Dispatcher).to have_received(:dispatch).exactly(3).times
  end

  it "registra resposta livre sem reaproveitar o botão anterior e mantém seu histórico" do
    first = reply("Visitar", "in-1")
    reply(nil, "in-2")
    expect(message.reload.reply_button_text).to be_nil
    expect(first.reload.button_text).to eq("Visitar")
    expect(metrics.totals).to include(interactions: 1, clicks: 1, free_responses: 1)
    expect { first.update!(button_text: "Apagado") }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "mantém os botões antigos mesmo depois que o template é alterado" do
    reply("Visitar", "in-1")
    template.update!(buttons: {"0" => {"kind" => "quick_reply", "text" => "Agendar visita"}})
    campaign.reload
    expect(metrics.button_cards(campaign).map { |c| c[:label] }).to include("Visitar", "Agendar visita")
  end

  it "não considera lead já vinculado como atendimento aceito" do
    message.update!(lead: create(:lead, tenant: tenant))
    reply("Visitar", "in-1")
    expect(campaign.attended_count).to eq(0)
    expect(metrics.totals[:outcomes]).not_to have_key("attendance_started")
  end

  it "conta ações por destinatário e preserva eventos sem confundir com o clique" do
    response = reply("Visitar", "in-1")
    2.times { WhatsappCampaignInteraction.record_action!(response: response, action_key: "create_task", label: "Criou tarefa", outcome: "task_created", metadata: {task_id: 1}) }
    WhatsappCampaignInteraction.record_action!(response: response, action_key: "open_attendance", label: "Encaminhou", outcome: "forwarded")
    expect(message.interactions.actions.where(outcome: %w[task_created forwarded]).count).to eq(2)
    expect(metrics.totals[:outcomes]).to include("task_created" => 1, "forwarded" => 1)
    expect(campaign.attended_count).to eq(0)
  end

  it "conta uma pessoa por campanha mesmo com duas mensagens para o mesmo telefone" do
    reply("Visitar", "in-1")
    other = campaign.campaign_messages.create!(phone_number: message.phone_number, status: "sent", sent_at: Time.current)
    reply("Visitar", "in-2", target: other)
    expect(metrics.totals).to include(interactions: 1, clicks: 2)
    expect(metrics.button_cards(campaign).first[:count]).to eq(1)
  end

  it "preserva o último registro antigo disponível antes de receber a nova resposta" do
    message.update!(status: "replied", reply_button_text: "Visitar", replied_at: 1.day.ago)
    expect(metrics.totals).to include(interactions: 1, clicks: 1, history_incomplete: true)
    reply("Condições", "in-1")
    expect(message.interactions.responses.order(:occurred_at).pluck(:button_text)).to eq(["Visitar", "Condições"])
    expect(message.interactions.responses.find_by(button_text: "Visitar").metadata["legacy_snapshot"]).to be(true)
    expect(metrics.totals).to include(interactions: 1, clicks: 2)
  end

  it "exclui campanhas de outro tenant mesmo que o escopo recebido contenha todas" do
    reply("Visitar", "in-1")
    foreign = Tenant.create!(name: "Outra", slug: "metric-scope")
    expect(described_class.new(tenant: foreign, campaigns: WhatsappCampaign.all).totals[:interactions]).to eq(0)
  end

  it "atribui um clique com contexto à mensagem original e ao número correto" do
    reply("Visitar", "in-1")
    newer = tenant.whatsapp_campaigns.create!(name: "Mais nova", whatsapp_template: template, whatsapp_sender_number: sender, created_by: admin, status: "completed")
    newer.campaign_messages.create!(phone_number: message.phone_number, status: "sent", sent_at: 1.minute.from_now)
    inbound = conversation.messages.create!(direction: "inbound", wa_message_id: "in-context", body: "Condições", msg_type: "button")
    processor = Whatsapp::InboundProcessor.new({})
    processor.instance_variable_set(:@tenant, tenant)
    processor.send(:mark_campaign_reply!, conversation, inbound, raw_message: {"id" => "in-context", "context" => {"id" => "outbound-1"}, "type" => "button", "button" => {"text" => "Condições"}})
    expect(message.interactions.responses.count).to eq(2)
    expect(newer.interactions).to be_empty
  end

  it "não adivinha outra campanha quando há referência explícita desconhecida" do
    message
    inbound = conversation.messages.create!(direction: "inbound", wa_message_id: "in-unknown", body: "Oi", msg_type: "text")
    processor = Whatsapp::InboundProcessor.new({})
    processor.instance_variable_set(:@tenant, tenant)
    processor.send(:mark_campaign_reply!, conversation, inbound, raw_message: {"context" => {"id" => "not-a-campaign"}})
    expect(campaign.interactions).to be_empty
  end
  it "registra tarefa somente depois de criá-la, sem confundir com atendimento" do
    lead = create(:lead, tenant: tenant, admin_user: admin)
    message.update!(lead: lead)
    response = reply("Visitar", "in-task")
    event = tenant.automation_events.create!(name: "whatsapp_campaign_message_replied", source: "whatsapp_campaign", lead: lead,
      payload: {whatsapp_campaign_id: campaign.id, whatsapp_campaign_message_id: message.id, campaign_interaction_id: response.id})
    executor = Automation::ActionExecutor.new(lead, automation_event: event)
    expect { executor.execute(type: "create_task", title: "Visita") }.to change(Task, :count).by(1)
    expect(metrics.totals[:outcomes]).to include("task_created" => 1)
    expect(campaign.attended_count).to eq(0)
  end

  it "só considera atendimento iniciado após o aceite real da conversa" do
    response = reply("Visitar", "in-attendance")
    lead = create(:lead, tenant: tenant, admin_user: admin)
    conversation.update!(lead: lead)
    manager = Whatsapp::AttendanceManager
    allow(manager).to receive(:resolve).and_return([nil, admin, [admin.id]])
    allow(manager).to receive(:assign).and_return(true)
    allow(manager).to receive(:notify)
    allow(manager).to receive(:broadcast_change)
    allow(manager).to receive(:schedule_acceptance)
    attendance = manager.open!(conversation: conversation, lead: lead, flow: nil,
      action: {"button_key" => "visita", "button_text" => "Visitar"}, campaign_interaction: response)
    expect(attendance).to be_persisted
    expect(campaign.attended_count).to eq(0)
    expect(metrics.totals[:outcomes]).to include("forwarded" => 1)
    manager.accept!(conversation.reload, admin)
    manager.accept!(conversation.reload, admin)
    expect(campaign.attended_count).to eq(1)
    expect(message.interactions.actions.where(outcome: "attendance_started").count).to eq(1)
  end

  it "recusa registrar uma resposta de outro destinatário" do
    inbound = tenant.whatsapp_conversations.create!(contact_phone: "5511888880000").messages.create!(direction: "inbound", body: "Visitar", wa_message_id: "foreign-recipient")
    expect { message.mark_replied!(inbound_message: inbound, raw_payload: {"type" => "button", "button" => {"text" => "Visitar"}}) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(message.interactions).to be_empty
  end

  it "não inventa outro clique ao receber novamente a resposta do último snapshot antigo" do
    message.update!(status: "replied", reply_button_text: "Visitar", reply_payload: {id: "same-old-id"}, replied_at: 1.day.ago)
    response = message.mark_replied!(raw_payload: {"id" => "same-old-id", "type" => "button", "button" => {"text" => "Visitar"}})
    expect(message.interactions.responses.count).to eq(1)
    expect(response.metadata["legacy_snapshot"]).to be(true)
    expect(Automation::Dispatcher).not_to have_received(:dispatch)
  end

  it "prefere a identidade do botão ao texto e não adivinha texto ambíguo" do
    template.update!(buttons: {"0" => {"kind" => "quick_reply", "text" => "Visitar"}, "1" => {"kind" => "quick_reply", "text" => "Visitar"}})
    campaign.reload
    key = campaign.response_decision_rows.last["key"]
    expect(campaign.response_decision_for(button_text: "Visitar", button_payload: key)["key"]).to eq(key)
    expect(campaign.response_decision_for(button_text: "Visitar")).to be_empty
  end

end
