require "rails_helper"

RSpec.describe "Conversa automática por botões", type: :service do
  include ActiveJob::TestHelper

  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  let(:tenant) { Tenant.default }
  let(:agent) { create(:admin_user, tenant: tenant) }
  let(:rule) { create(:distribution_rule, tenant: tenant) }
  let!(:rule_agent) { create(:distribution_rule_agent, tenant: tenant, distribution_rule: rule, admin_user: agent, position: 1) }
  let(:template) do
    tenant.whatsapp_templates.create!(
      name: "menu_auto", language: "pt_BR", status: "APPROVED", usage_context: "response_flow", waba_id: "waba-auto",
      category: "UTILITY", body: "Como podemos ajudar?", buttons: [{ "kind" => "quick_reply", "text" => "Falar com a equipe" }]
    )
  end
  let(:button) { template.interactive_buttons.first }
  let(:definition) do
    {
      "schema_version" => 1,
      "nodes" => [
        { "id" => "entry_1", "type" => "entry", "label" => "Clique", "config" => { "trigger" => "whatsapp_flow_button", "entry_policy" => "future" } },
        { "id" => "ask_1", "type" => "action", "label" => "Pergunta", "config" => { "action_type" => "send_whatsapp_buttons", "message" => "Quer comprar ou alugar?", "options" => "Comprar\nAlugar" } },
        { "id" => "wait_1", "type" => "await_whatsapp_response", "label" => "Aguardar", "config" => { "timeout_amount" => "2", "timeout_unit" => "hours" } },
        { "id" => "buy", "type" => "response_condition", "label" => "Comprar", "config" => { "category" => "template_buttons", "field" => "interaction.button_text", "operator" => "equals", "value" => "Comprar" } },
        { "id" => "transfer", "type" => "action", "label" => "Atendente", "config" => { "action_type" => "transfer_to_attendant", "distribution_rule_id" => rule.id.to_s, "topic" => "Compra de imóvel" } },
        { "id" => "rent", "type" => "response_condition", "label" => "Alugar", "config" => { "category" => "template_buttons", "field" => "interaction.button_text", "operator" => "equals", "value" => "Alugar" } },
        { "id" => "rent_reply", "type" => "action", "label" => "Resposta", "config" => { "action_type" => "send_whatsapp", "message" => "Vamos de locação!" } },
        { "id" => "unknown", "type" => "response_fallback", "label" => "Não entendi", "config" => { "fallback_type" => "no_match" } },
        { "id" => "unknown_reply", "type" => "action", "label" => "Aviso", "config" => { "action_type" => "send_whatsapp", "message" => "Não entendi." } }
      ],
      "edges" => [
        { "from" => "entry_1", "to" => "ask_1" }, { "from" => "ask_1", "to" => "wait_1" },
        { "from" => "wait_1", "to" => "buy" }, { "from" => "buy", "to" => "transfer" },
        { "from" => "wait_1", "to" => "rent" }, { "from" => "rent", "to" => "rent_reply" },
        { "from" => "wait_1", "to" => "unknown" }, { "from" => "unknown", "to" => "unknown_reply" }
      ]
    }
  end
  let!(:workflow) do
    tenant.automation_workflows.create!(name: "Conversa de teste").tap do |record|
      version = record.versions.create!(version_number: 1, status: "draft", definition: definition)
      record.publish!(version: version)
    end
  end
  let!(:flow) do
    tenant.whatsapp_response_flows.create!(
      name: "Menu", whatsapp_template: template,
      button_actions: { button["key"] => { "button_key" => button["key"], "button_text" => button["text"], "action" => "run_automation", "automation_workflow_id" => workflow.id.to_s } }
    )
  end
  let(:conversation) { tenant.whatsapp_conversations.create!(contact_phone: "5547999994321", contact_name: "Cliente Auto") }

  before do
    allow(Whatsapp::SendMessageJob).to receive(:dispatch)
    allow(Whatsapp::ThreadBroadcaster).to receive(:message_created)
    allow(ActionCable.server).to receive(:broadcast)
  end

  # Executa só os jobs imediatos; os agendados (timeout da espera) ficam na fila, como em produção.
  def run_jobs
    loop do
      entry = queue_adapter.enqueued_jobs.find { |job| job[:at].nil? }
      break unless entry

      queue_adapter.enqueued_jobs.delete(entry)
      entry[:job].perform_now(*ActiveJob::Arguments.deserialize(entry[:args]))
    end
  end

  def click_menu_button
    conversation.messages.create!(direction: "outbound", msg_type: "template", template_name: template.name, body: template.body, status: "sent", wa_message_id: "wamid.menu.#{SecureRandom.hex(3)}")
    inbound = conversation.messages.create!(direction: "inbound", msg_type: "button", body: button["text"], status: "delivered")
    Whatsapp::ResponseFlowRunner.call(
      conversation: conversation, inbound_message: inbound,
      raw_message: { type: "button", context: { id: conversation.messages.outbound.last.wa_message_id }, button: { text: button["text"], payload: button["key"] } }
    )
    run_jobs
    # Mesmo clique chegando como evento de WhatsApp recebido (como no InboundProcessor).
    Automation::Dispatcher.dispatch(:whatsapp_received, conversation.reload.lead, source: "whatsapp", payload: { whatsapp_message_id: inbound.id }, idempotency_key: "wr:#{inbound.id}")
    run_jobs
  end

  def answer(text)
    inbound = conversation.messages.create!(direction: "inbound", msg_type: "interactive", body: text, status: "delivered")
    Automation::Dispatcher.dispatch(:whatsapp_received, conversation.reload.lead, source: "whatsapp", payload: { whatsapp_message_id: inbound.id }, idempotency_key: "wr:#{inbound.id}")
    run_jobs
  end

  it "o clique no botao inicia a conversa, faz a pergunta com botoes e espera sem tratar o clique como resposta" do
    click_menu_button

    question = conversation.messages.outbound.find_by(msg_type: "interactive")
    expect(question.body).to eq("Quer comprar ou alugar?")
    expect(question.template_components.map { |item| item["title"] }).to eq(%w[Comprar Alugar])
    execution = AutomationExecution.last
    expect(execution.status).to eq("waiting")
    expect(execution.steps.where(node_type: "response_fallback")).to be_empty # o clique não virou "resposta não reconhecida"
    expect(conversation.messages.outbound.where(body: "Não entendi.")).to be_empty
  end

  it "a resposta escolhe o caminho: Comprar passa para atendente com as respostas anotadas" do
    click_menu_button

    answer("Comprar")

    attendance = conversation.reload.open_attendance
    expect(attendance).to have_attributes(button_text: "Compra de imóvel", admin_user: agent)
    note = LeadActivity.where(lead: conversation.lead, kind: "note").last
    expect(note.metadata["body"]).to include("Quer comprar ou alugar? — Comprar")
  end

  it "outra opcao segue o proprio caminho e uma resposta fora do esperado cai no fallback" do
    click_menu_button
    answer("Alugar")
    expect(conversation.messages.outbound.where(body: "Vamos de locação!")).to exist
    expect(conversation.reload.open_attendance).to be_nil

    other = conversation.tenant.whatsapp_conversations.create!(contact_phone: "5547999994322", contact_name: "Outro")
    inbound = other.messages.create!(direction: "inbound", msg_type: "button", body: button["text"], status: "delivered")
    Whatsapp::ResponseFlowRunner.call(conversation: other, inbound_message: inbound, raw_message: { type: "button", button: { text: button["text"], payload: button["key"] } })
    run_jobs
    typed = other.messages.create!(direction: "inbound", msg_type: "text", body: "talvez", status: "delivered")
    Automation::Dispatcher.dispatch(:whatsapp_received, other.reload.lead, source: "whatsapp", payload: { whatsapp_message_id: typed.id }, idempotency_key: "wr:#{typed.id}")
    run_jobs

    expect(other.messages.outbound.where(body: "Não entendi.")).to exist
  end

  it "nao devolve o menu enquanto o cliente esta respondendo a automacao" do
    click_menu_button
    typed = conversation.messages.create!(direction: "inbound", msg_type: "text", body: "oi?", status: "delivered")
    conversation.attendances.create!(tenant: tenant, status: "closed", opened_at: 2.days.ago, closed_at: 1.day.ago, button_text: "Antigo") # já houve atendimento antes

    Whatsapp::ResponseFlowRunner.call(conversation: conversation, inbound_message: typed, raw_message: { type: "text", text: { body: "oi?" } })

    expect(conversation.messages.outbound.where(msg_type: "template").count).to eq(1) # só o menu original
  end

  it "voltar ao menu cancela a conversa anterior que ainda esperava resposta" do
    click_menu_button
    first = AutomationExecution.last

    click_menu_button

    expect(first.reload.status).to eq("canceled")
    expect(AutomationExecution.where(status: "waiting").count).to eq(1)
  end

  it "a pergunta com lista sai como mensagem interativa de lista" do
    action = { "type" => "send_whatsapp_list", "message" => "Escolha:", "options" => %w[Casa Apartamento], "list_button" => "Ver tipos" }
    conversation.update!(lead: create(:lead, tenant: tenant, admin_user: agent))
    Automation::ActionExecutor.new(conversation.lead).execute(action)

    message = conversation.messages.outbound.last
    expect(message.msg_type).to eq("interactive_list")
    expect(message.template_components).to include("button" => "Ver tipos", "rows" => [{ "id" => "aq:0", "title" => "Casa" }, { "id" => "aq:1", "title" => "Apartamento" }])
  end

  describe "\"não entendi\" que repete a pergunta e depois passa para atendente" do
    let(:retry_definition) do
      {
        "schema_version" => 1,
        "nodes" => [
          { "id" => "entry_1", "type" => "entry", "label" => "Clique", "config" => { "trigger" => "whatsapp_flow_button", "entry_policy" => "future" } },
          { "id" => "ask_1", "type" => "action", "label" => "Pergunta", "config" => { "action_type" => "send_whatsapp_buttons", "message" => "Comprar ou alugar?", "options" => "Comprar\nAlugar" } },
          { "id" => "wait_1", "type" => "await_whatsapp_response", "label" => "Aguardar", "config" => { "timeout_amount" => "2", "timeout_unit" => "hours" } },
          { "id" => "buy", "type" => "response_condition", "label" => "Comprar", "config" => { "category" => "template_buttons", "field" => "interaction.button_text", "operator" => "equals", "value" => "Comprar" } },
          { "id" => "buy_reply", "type" => "action", "label" => "Ótimo", "config" => { "action_type" => "send_whatsapp", "message" => "Ótima escolha!" } },
          { "id" => "unknown", "type" => "response_fallback", "label" => "Não entendi", "config" => { "fallback_type" => "no_match", "retry_question" => true, "max_attempts" => "2" } },
          { "id" => "unknown_reply", "type" => "action", "label" => "Aviso", "config" => { "action_type" => "send_whatsapp", "message" => "Não entendi. Vou perguntar de novo." } },
          { "id" => "exhausted", "type" => "response_fallback", "label" => "Depois de 2", "config" => { "fallback_type" => "exhausted" } },
          { "id" => "exhausted_reply", "type" => "action", "label" => "Chamar", "config" => { "action_type" => "send_whatsapp", "message" => "Vou chamar um atendente." } },
          { "id" => "handoff", "type" => "action", "label" => "Atendente", "config" => { "action_type" => "transfer_to_attendant", "distribution_rule_id" => rule.id.to_s, "topic" => "Sem entendimento" } }
        ],
        "edges" => [
          { "from" => "entry_1", "to" => "ask_1" }, { "from" => "ask_1", "to" => "wait_1" },
          { "from" => "wait_1", "to" => "buy" }, { "from" => "buy", "to" => "buy_reply" },
          { "from" => "wait_1", "to" => "unknown" }, { "from" => "unknown", "to" => "unknown_reply" },
          { "from" => "wait_1", "to" => "exhausted" }, { "from" => "exhausted", "to" => "exhausted_reply" }, { "from" => "exhausted_reply", "to" => "handoff" }
        ]
      }
    end

    before do
      workflow.versions.create!(version_number: 2, status: "draft", definition: retry_definition).tap { |version| workflow.publish!(version: version) }
    end

    def questions = conversation.messages.outbound.where(msg_type: "interactive", body: "Comprar ou alugar?").count

    it "repete a pergunta ate o limite e depois entrega a um atendente" do
      click_menu_button
      expect(questions).to eq(1)

      answer("sei lá")
      expect(conversation.messages.outbound.where(body: "Não entendi. Vou perguntar de novo.").count).to eq(1)
      expect(questions).to eq(2)

      answer("talvez")
      expect(questions).to eq(3)
      expect(conversation.reload.open_attendance).to be_nil

      answer("hmm")
      expect(questions).to eq(3) # não pergunta de novo
      expect(conversation.messages.outbound.where(body: "Vou chamar um atendente.")).to exist
      expect(conversation.reload.open_attendance).to have_attributes(button_text: "Sem entendimento", admin_user: agent)
    end

    it "uma resposta reconhecida zera a contagem" do
      click_menu_button
      answer("sei lá")
      answer("Comprar")

      expect(conversation.messages.outbound.where(body: "Ótima escolha!")).to exist
      expect(AutomationExecution.last.context["no_match_attempts"].to_h).to be_empty
    end

    it "sem repeticao configurada o comportamento antigo continua: so o aviso" do
      no_retry = retry_definition.deep_dup
      no_retry["nodes"].find { |node| node["id"] == "unknown" }["config"] = { "fallback_type" => "no_match" }
      no_retry["nodes"].reject! { |node| %w[exhausted exhausted_reply handoff].include?(node["id"]) }
      no_retry["edges"].reject! { |edge| %w[exhausted exhausted_reply handoff].include?(edge["from"]) || %w[exhausted exhausted_reply handoff].include?(edge["to"]) }
      workflow.versions.create!(version_number: 3, status: "draft", definition: no_retry).tap { |version| workflow.publish!(version: version) }

      click_menu_button
      answer("sei lá")

      expect(conversation.messages.outbound.where(body: "Não entendi. Vou perguntar de novo.").count).to eq(1)
      expect(questions).to eq(1)
    end
  end
end
