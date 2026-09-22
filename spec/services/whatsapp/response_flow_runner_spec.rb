require "rails_helper"

RSpec.describe Whatsapp::ResponseFlowRunner do
  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  let(:tenant) { Tenant.default }
  let(:broker) { create(:admin_user, tenant: tenant) }
  let(:rule) { create(:distribution_rule, tenant: tenant) }
  let!(:agent) { create(:distribution_rule_agent, tenant: tenant, distribution_rule: rule, admin_user: broker, position: 1) }
  let(:template) do
    tenant.whatsapp_templates.create!(
      name: "menu_atendimento",
      language: "pt_BR",
      status: "APPROVED",
      usage_context: "response_flow",
      waba_id: "waba-menu",
      category: "UTILITY",
      body: "Como podemos ajudar?",
      buttons: { "0" => { "kind" => "quick_reply", "text" => "Comprar ou Investir" } }
    )
  end
  let(:button) { template.interactive_buttons.first }
  let!(:flow) do
    tenant.whatsapp_response_flows.create!(
      name: "Menu principal",
      whatsapp_template: template,
      button_actions: {
        button["key"] => {
          "button_key" => button["key"],
          "button_text" => button["text"],
          "action" => "distribute_lead",
          "distribution_rule_id" => rule.id,
          "inside_hours_message" => "Só um momento, um atendente irá entrar em contato.",
          "business_hours" => {
            "enabled" => "0",
            "days" => %w[mon tue wed thu fri],
            "start" => "08:00",
            "end" => "18:00"
          }
        }
      }
    )
  end

  it "executa a acao do botao e distribui a conversa para a regra configurada" do
    allow(Whatsapp::SendMessageJob).to receive(:dispatch)
    allow(Whatsapp::ThreadBroadcaster).to receive(:message_created)
    conversation = tenant.whatsapp_conversations.create!(contact_phone: "5547999991111", contact_name: "Maria")
    outbound = conversation.messages.create!(direction: "outbound", msg_type: "template", template_name: template.name, body: template.body, status: "sent", wa_message_id: "wamid.menu")
    inbound = conversation.messages.create!(direction: "inbound", msg_type: "button", body: button["text"], status: "delivered")
    raw = {
      type: "button",
      context: { id: outbound.wa_message_id },
      button: { text: button["text"], payload: button["key"] }
    }

    described_class.call(conversation: conversation, inbound_message: inbound, raw_message: raw)

    lead = conversation.reload.lead
    expect(lead).to be_present
    expect(lead.distribution_rule).to eq(rule)
    expect(lead.admin_user).to eq(broker)
    expect(conversation.assigned_admin_user).to eq(broker)
    expect(conversation.messages.outbound.last.body).to eq("Só um momento, um atendente irá entrar em contato.")
    expect(lead.activities.where(kind: "whatsapp_response_flow")).to exist
  end

  it "direciona para o atendente escolhido na regra" do
    target_broker = create(:admin_user, tenant: tenant)
    create(:distribution_rule_agent, tenant: tenant, distribution_rule: rule, admin_user: target_broker, position: 2)
    flow.update!(
      button_actions: flow.button_actions.deep_merge(
        button["key"] => { "target_admin_user_id" => target_broker.id.to_s }
      )
    )
    allow(Whatsapp::SendMessageJob).to receive(:dispatch)
    allow(Whatsapp::ThreadBroadcaster).to receive(:message_created)
    conversation = tenant.whatsapp_conversations.create!(contact_phone: "5547999993333", contact_name: "Joana")
    outbound = conversation.messages.create!(direction: "outbound", msg_type: "template", template_name: template.name, body: template.body, status: "sent", wa_message_id: "wamid.menu.direct")
    inbound = conversation.messages.create!(direction: "inbound", msg_type: "button", body: button["text"], status: "delivered")

    described_class.call(
      conversation: conversation,
      inbound_message: inbound,
      raw_message: {
        type: "button",
        context: { id: outbound.wa_message_id },
        button: { text: button["text"], payload: button["key"] }
      }
    )

    expect(conversation.reload.assigned_admin_user).to eq(target_broker)
    expect(conversation.lead.admin_user).to eq(target_broker)
    expect(conversation.lead.status).to eq(Lead.status_value(:em_atendimento))
  end

  def click_button!(phone:)
    allow(Whatsapp::SendMessageJob).to receive(:dispatch)
    allow(Whatsapp::ThreadBroadcaster).to receive(:message_created)
    conversation = tenant.whatsapp_conversations.create!(contact_phone: phone, contact_name: "Contato")
    outbound = conversation.messages.create!(direction: "outbound", msg_type: "template", template_name: template.name, body: template.body, status: "sent", wa_message_id: "wamid.#{phone}")
    inbound = conversation.messages.create!(direction: "inbound", msg_type: "button", body: button["text"], status: "delivered")
    described_class.call(
      conversation: conversation,
      inbound_message: inbound,
      raw_message: { type: "button", context: { id: outbound.wa_message_id }, button: { text: button["text"], payload: button["key"] } }
    )
    conversation.reload
  end

  it "restringe o rodizio aos atendentes marcados no botao" do
    chosen = create(:admin_user, tenant: tenant)
    other = create(:admin_user, tenant: tenant)
    create(:distribution_rule_agent, tenant: tenant, distribution_rule: rule, admin_user: chosen, position: 5)
    create(:distribution_rule_agent, tenant: tenant, distribution_rule: rule, admin_user: other, position: 0)
    flow.update!(button_actions: flow.button_actions.deep_merge(button["key"] => { "target_admin_user_ids" => [chosen.id.to_s, broker.id.to_s] }))

    conversation = click_button!(phone: "5547999995555")

    expect([chosen, broker]).to include(conversation.lead.admin_user)
    expect(conversation.lead.admin_user).not_to eq(other)
  end

  it "envia o lead direto para o usuario escolhido" do
    user = create(:admin_user, tenant: tenant)
    flow.update!(button_actions: { button["key"] => { "button_key" => button["key"], "button_text" => button["text"], "action" => "send_to_user", "target_user_id" => user.id.to_s } })

    conversation = click_button!(phone: "5547999996666")

    expect(conversation.assigned_admin_user).to eq(user)
    expect(conversation.lead.admin_user).to eq(user)
    expect(conversation.lead.status).to eq(Lead.status_value(:em_atendimento))
  end

  describe "resposta automatica" do
    def click_with(action_attrs)
      flow.update!(button_actions: { button["key"] => { "button_key" => button["key"], "button_text" => button["text"] }.merge(action_attrs) })
      allow(Whatsapp::SendMessageJob).to receive(:dispatch)
      allow(Whatsapp::ThreadBroadcaster).to receive(:message_created)
      conversation = tenant.whatsapp_conversations.create!(contact_phone: "5547999997777", contact_name: "Ana")
      outbound = conversation.messages.create!(direction: "outbound", msg_type: "template", template_name: template.name, body: template.body, status: "sent", wa_message_id: "wamid.auto")
      inbound = conversation.messages.create!(direction: "inbound", msg_type: "button", body: button["text"], status: "delivered")
      described_class.call(conversation: conversation, inbound_message: inbound,
                           raw_message: { type: "button", context: { id: outbound.wa_message_id }, button: { text: button["text"], payload: button["key"] } })
      conversation.messages.outbound.where(msg_type: "text").last&.body
    end

    it "envia a mensagem automatica digitada quando nao ha horario de atendimento" do
      expect(click_with("action" => "send_message", "message" => "Olá! Já te respondo.")).to eq("Olá! Já te respondo.")
    end

    it "usa a mensagem dentro do horario quando o horario esta ligado" do
      body = click_with("action" => "send_message", "message" => "Olá!", "inside_hours_message" => "Estamos online.",
                        "business_hours" => { "enabled" => "1", "days" => WhatsappResponseFlow::DAY_KEYS, "start" => "00:00", "end" => "23:59" })
      expect(body).to eq("Estamos online.")
    end

    it "envia o link junto da mensagem em Enviar link" do
      body = click_with("action" => "send_url", "url" => "https://salute.com.br/imoveis", "message" => "Veja nossos imóveis:")
      expect(body).to eq("Veja nossos imóveis:\nhttps://salute.com.br/imoveis")
    end

    it "envia so o link quando nao ha mensagem e ignora o horario de atendimento" do
      body = click_with("action" => "send_url", "url" => "https://salute.com.br/imoveis", "business_hours" => { "enabled" => "1", "days" => [], "start" => "08:00", "end" => "18:00" })
      expect(body).to eq("https://salute.com.br/imoveis")
    end
  end

  describe "criar tarefa" do
    def click_task(action_attrs, lead_owner: nil)
      flow.update!(button_actions: { button["key"] => { "button_key" => button["key"], "button_text" => button["text"], "action" => "create_task" }.merge(action_attrs) })
      allow(Whatsapp::SendMessageJob).to receive(:dispatch)
      allow(Whatsapp::ThreadBroadcaster).to receive(:message_created)
      lead = tenant.leads.create!(name: "Ana Lead", phone: "5547999998888", origin: "whatsapp", status: Lead.default_status)
      lead.update_column(:admin_user_id, lead_owner&.id) # o cadastro pode atribuir corretor sozinho; aqui o cenário é explícito
      conversation = tenant.whatsapp_conversations.create!(contact_phone: "5547999998888", contact_name: "Ana", lead: lead)
      outbound = conversation.messages.create!(direction: "outbound", msg_type: "template", template_name: template.name, body: template.body, status: "sent", wa_message_id: "wamid.task")
      inbound = conversation.messages.create!(direction: "inbound", msg_type: "button", body: button["text"], status: "delivered")
      described_class.call(conversation: conversation, inbound_message: inbound,
                           raw_message: { type: "button", context: { id: outbound.wa_message_id }, button: { text: button["text"], payload: button["key"] } })
      conversation
    end

    it "usa titulo, prazo, tipo e prioridade do botao, fica com o corretor do lead, avisa e confirma ao cliente" do
      other = create(:admin_user, tenant: tenant)
      conversation = click_task({ "task_title" => "Ligar para a Ana", "task_user_id" => other.id.to_s, "task_due_minutes" => 240, "task_kind" => "ligacao",
                                  "task_priority" => "alta", "message" => "Recebemos! Já vamos te ligar." }, lead_owner: broker)

      task = Task.order(:id).last
      expect(task).to have_attributes(title: "Ligar para a Ana", admin_user_id: broker.id, kind: "ligacao", priority: "alta", lead_id: conversation.lead.id, source: "automation")
      expect(task.due_at).to be_within(1.minute).of(4.hours.from_now)
      expect(task.description).to include("Comprar ou Investir").and include("Ana")
      expect(InAppNotification.where(admin_user: broker, kind: "whatsapp_task").last.title).to eq("Nova tarefa: Ligar para a Ana")
      expect(conversation.messages.outbound.where(msg_type: "text").last.body).to eq("Recebemos! Já vamos te ligar.")
    end

    it "sem configuracao extra vai para o responsavel do lead, em 2 horas, como follow-up" do
      click_task({}, lead_owner: broker)

      expect(Task.order(:id).last).to have_attributes(admin_user_id: broker.id, kind: "follow_up", priority: "normal", title: "Acompanhar resposta WhatsApp: Comprar ou Investir")
      expect(Task.order(:id).last.due_at).to be_within(1.minute).of(2.hours.from_now)
    end

    it "sem corretor no lead, cria tarefa pessoal para o usuario definido no botao" do
      user = create(:admin_user, tenant: tenant)
      click_task({ "task_user_id" => user.id.to_s })

      expect(Task.order(:id).last).to have_attributes(admin_user_id: user.id, lead_id: nil)
    end

    it "nao cria a tarefa quando ninguem pode recebe-la" do
      expect { click_task({}) }.not_to change(Task, :count)
    end

    it "ignora horario de atendimento antigo em uma acao que nao o usa" do
      user = create(:admin_user, tenant: tenant)
      flow.update!(button_actions: { button["key"] => { "button_key" => button["key"], "button_text" => button["text"], "action" => "create_task", "message" => "Oi",
                                                        "business_hours" => { "enabled" => "1", "days" => [], "start" => "08:00", "end" => "18:00" } } })
      expect(flow.button_actions[button["key"]].dig("business_hours", "enabled")).to eq("0")
    end
  end

  it "usa o fluxo receptivo do numero quando a resposta chega sem contexto de template" do
    sender = create(:whatsapp_sender_number, tenant: tenant, waba_id: template.waba_id, phone_number_id: "phone-menu", receptive_response_flow: flow)
    allow(Whatsapp::SendMessageJob).to receive(:dispatch)
    allow(Whatsapp::ThreadBroadcaster).to receive(:message_created)
    conversation = tenant.whatsapp_conversations.create!(contact_phone: "5547999994444", contact_name: "Julia")
    inbound = conversation.messages.create!(direction: "inbound", msg_type: "button", body: button["text"], status: "delivered")

    described_class.call(
      conversation: conversation,
      inbound_message: inbound,
      raw_message: { type: "button", button: { text: button["text"], payload: button["key"] } },
      phone_number_id: sender.phone_number_id
    )

    expect(conversation.reload.assigned_admin_user).to eq(broker)
    expect(conversation.lead.distribution_rule).to eq(rule)
  end

  it "nao duplica a acao quando a campanha ja possui decisoes locais" do
    campaign = tenant.whatsapp_campaigns.create!(
      name: "Campanha com decisões",
      whatsapp_template: template,
      created_by: broker,
      response_decisions: {
        buttons: [{ key: button["key"], text: button["text"], action: "generate_lead", distribution_rule_id: rule.id }]
      }
    )
    campaign_message = campaign.campaign_messages.create!(phone_number: "5547999992222", status: "sent")
    conversation = tenant.whatsapp_conversations.create!(contact_phone: "5547999992222")
    inbound = conversation.messages.create!(direction: "inbound", msg_type: "button", body: button["text"], status: "delivered")

    expect {
      described_class.call(
        conversation: conversation,
        inbound_message: inbound,
        raw_message: { type: "button", button: { text: button["text"], payload: button["key"] } },
        campaign_message: campaign_message
      )
    }.not_to change(Lead, :count)
  end
end
