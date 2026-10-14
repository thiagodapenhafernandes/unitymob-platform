require "rails_helper"

RSpec.describe "Fluxo que guarda a resposta do cliente", type: :service do
  include ActiveJob::TestHelper

  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  let(:tenant) { Tenant.default }
  let(:lead) { create(:lead, tenant: tenant, name: "Contato", email: "antigo@exemplo.com", phone: "5547999994321") }
  let(:definition) do
    {
      "schema_version" => 1,
      "nodes" => [
        { "id" => "entry_1", "type" => "entry", "label" => "Início", "config" => { "trigger" => "lead_created", "entry_policy" => "future" } },
        { "id" => "ask", "type" => "action", "label" => "Pergunta", "config" => { "action_type" => "send_whatsapp", "message" => "Qual o seu e-mail?" } },
        { "id" => "wait", "type" => "await_whatsapp_response", "label" => "Aguardar", "config" => { "timeout_amount" => "2", "timeout_unit" => "hours" } },
        { "id" => "valid", "type" => "response_condition", "label" => "E-mail válido", "config" => { "category" => "lead_text", "field" => "message.body", "operator" => "valid_email", "value" => "" } },
        { "id" => "capture", "type" => "action", "label" => "Guardar", "config" => { "action_type" => "capture_answer", "variable" => "email", "answer_type" => "email", "lead_target" => "email" } },
        { "id" => "thanks", "type" => "action", "label" => "Obrigado", "config" => { "action_type" => "send_whatsapp", "message" => "Anotei {{resposta.email}}, {{nome}}!" } },
        { "id" => "invalid", "type" => "response_fallback", "label" => "Inválido", "config" => { "fallback_type" => "no_match", "retry_question" => "true", "max_attempts" => "2" } },
        { "id" => "invalid_reply", "type" => "action", "label" => "Aviso", "config" => { "action_type" => "send_whatsapp", "message" => "Esse e-mail não parece válido." } }
      ],
      "edges" => [
        { "from" => "entry_1", "to" => "ask" }, { "from" => "ask", "to" => "wait" },
        { "from" => "wait", "to" => "valid" }, { "from" => "valid", "to" => "capture" }, { "from" => "capture", "to" => "thanks" },
        { "from" => "wait", "to" => "invalid" }, { "from" => "invalid", "to" => "invalid_reply" }
      ]
    }
  end
  let!(:workflow) do
    tenant.automation_workflows.create!(name: "Captura de e-mail").tap do |record|
      version = record.versions.create!(version_number: 1, status: "draft", definition: definition)
      record.publish!(version: version)
    end
  end
  let(:conversation) { tenant.whatsapp_conversations.find_by!(contact_phone: "5547999994321") }

  before do
    allow(Whatsapp::SendMessageJob).to receive(:dispatch)
    allow(Whatsapp::ThreadBroadcaster).to receive(:message_created)
    allow(ActionCable.server).to receive(:broadcast)
  end

  def run_jobs
    loop do
      entry = queue_adapter.enqueued_jobs.find { |job| job[:at].nil? }
      break unless entry

      queue_adapter.enqueued_jobs.delete(entry)
      entry[:job].perform_now(*ActiveJob::Arguments.deserialize(entry[:args]))
    end
  end

  # Criar o lead dispara o gatilho `lead_created` e inicia o fluxo sozinho.
  def start_flow
    lead
    run_jobs
  end

  def answer(text)
    inbound = conversation.messages.create!(direction: "inbound", msg_type: "text", body: text, status: "delivered")
    Automation::Dispatcher.dispatch(:whatsapp_received, lead.reload, source: "whatsapp", payload: { whatsapp_message_id: inbound.id }, idempotency_key: "wr:#{inbound.id}")
    run_jobs
  end

  it "valida a resposta, guarda a variavel, grava no lead e usa a variavel na mensagem seguinte" do
    start_flow
    expect(conversation.messages.outbound.pluck(:body)).to eq(["Qual o seu e-mail?"])

    answer("Maria@Exemplo.com")

    execution = AutomationExecution.last
    expect(execution.context["variables"]).to eq("email" => "maria@exemplo.com")
    expect(lead.reload.email).to eq("maria@exemplo.com")
    expect(conversation.messages.outbound.order(:id).last.body).to eq("Anotei maria@exemplo.com, #{lead.display_name}!")
    capture_step = execution.steps.find_by(node_id: "capture")
    expect(capture_step.output).to include("captured" => true, "lead_written" => true, "variable" => "email")
  end

  it "resposta invalida nao grava nada e repete a pergunta" do
    start_flow

    answer("meu email é segredo")

    expect(lead.reload.email).to eq("antigo@exemplo.com")
    expect(AutomationExecution.last.context["variables"]).to be_blank
    expect(conversation.messages.outbound.pluck(:body).count("Qual o seu e-mail?")).to eq(2)
  end

  describe "template com botoes no meio do fluxo" do
    let(:template) do
      tenant.whatsapp_templates.create!(
        name: "menu_meio", language: "pt_BR", status: "APPROVED", usage_context: "response_flow", waba_id: "waba-meio",
        category: "UTILITY", body: "Como podemos ajudar?", buttons: [{ "kind" => "quick_reply", "text" => "Falar com a equipe" }, { "kind" => "quick_reply", "text" => "Ver imóveis" }]
      )
    end
    let(:scaffold) { Automation::TemplateScaffold.call(template) }
    let(:conditions) { scaffold["nodes"].select { |node| node["type"] == "response_condition" } }
    let(:definition) do
      {
        "schema_version" => 1,
        "nodes" => [
          { "id" => "entry_1", "type" => "entry", "label" => "Início", "config" => { "trigger" => "lead_created", "entry_policy" => "future" } },
          { "id" => "send", "type" => "action", "label" => "Enviar template", "config" => { "action_type" => "send_whatsapp_template", "template" => template.name, "template_flow" => true } },
          { "id" => "wait", "type" => "await_whatsapp_response", "label" => "Aguardar", "config" => { "timeout_amount" => "2", "timeout_unit" => "hours" } },
          conditions[0].merge("id" => "team"), { "id" => "team_reply", "type" => "action", "label" => "Equipe", "config" => { "action_type" => "send_whatsapp", "message" => "A equipe vai falar com você, {{nome}}." } },
          conditions[1].merge("id" => "homes"), { "id" => "homes_reply", "type" => "action", "label" => "Imóveis", "config" => { "action_type" => "send_whatsapp", "message" => "Vou te mostrar imóveis." } },
          { "id" => "unknown", "type" => "response_fallback", "label" => "Não entendi", "config" => { "fallback_type" => "no_match" } },
          { "id" => "unknown_reply", "type" => "action", "label" => "Aviso", "config" => { "action_type" => "send_whatsapp", "message" => "Não entendi." } }
        ],
        "edges" => [
          { "from" => "entry_1", "to" => "send" }, { "from" => "send", "to" => "wait" },
          { "from" => "wait", "to" => "team" }, { "from" => "team", "to" => "team_reply" },
          { "from" => "wait", "to" => "homes" }, { "from" => "homes", "to" => "homes_reply" },
          { "from" => "wait", "to" => "unknown" }, { "from" => "unknown", "to" => "unknown_reply" }
        ]
      }
    end

    it "envia o template e o clique em cada botao segue o proprio caminho" do
      start_flow
      expect(conversation.messages.outbound.where(msg_type: "template").pluck(:template_name)).to eq([template.name])

      answer("Ver imóveis")

      bodies = conversation.messages.outbound.order(:id).pluck(:body)
      expect(bodies).to include("Vou te mostrar imóveis.")
      expect(bodies).not_to include("Não entendi.")
      expect(bodies.grep(/A equipe vai falar/)).to be_empty
    end
  end
end
