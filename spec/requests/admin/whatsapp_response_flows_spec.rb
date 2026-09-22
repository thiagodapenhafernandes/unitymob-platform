require "rails_helper"

RSpec.describe "Admin::WhatsappResponseFlows", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "wa-flow-#{SecureRandom.hex(6)}@salute.test") }
  let(:template) do
    admin.tenant.whatsapp_templates.create!(
      name: "menu_salute",
      language: "pt_BR",
      category: "UTILITY",
      status: "APPROVED",
      usage_context: "response_flow",
      waba_id: "waba-salute",
      body: "Como podemos ajudar?",
      buttons: [
        { "kind" => "quick_reply", "text" => "Comprar" },
        { "kind" => "quick_reply", "text" => "Manutenções" }
      ]
    )
  end

  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = admin.tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  before do
    host! "localhost"
    sign_in admin
  end

  describe "escolha do template" do
    it "lista sem o bloco de templates e com o botao Novo fluxo de resposta" do
      get admin_whatsapp_response_flows_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Templates aprovados")
      expect(response.body).not_to include("Fluxos configurados")
      expect(Nokogiri::HTML(response.body).at_css(".whatsapp-response-flows > .ax-table-wrap table.ax-table")).to be_present
      expect(response.body).to include("Novo fluxo de resposta").and include(new_admin_whatsapp_response_flow_path)
    end

    it "mostra na tabela quantos botoes tem acao e qual numero usa o fluxo como receptivo" do
      flow = admin.tenant.whatsapp_response_flows.create!(
        name: "Fluxo receptivo", whatsapp_template: template,
        button_actions: { "text:0:comprar" => { "button_key" => "text:0:comprar", "button_text" => "Comprar", "action" => "send_url", "url" => "https://salute.com.br" } }
      )
      sender = create(:whatsapp_sender_number, tenant: admin.tenant, waba_id: template.waba_id, display_phone_number: "5547999991111", receptive_response_flow: flow)

      get admin_whatsapp_response_flows_path

      row = Nokogiri::HTML(response.body).at_css("tbody tr")
      expect(row.text).to include("1 de 2").and include("Fluxo receptivo").and include(sender.formatted_phone)
      expect(row.at_css("a[href='#{edit_admin_whatsapp_response_flow_path(flow)}']")).to be_present
    end

    it "oferece a acao Iniciar automacao com a lista de automacoes que comecam por botao" do
      workflow = admin.tenant.automation_workflows.create!(name: "Conversa de teste")
      definition = Automation::TemplateScaffold.call(template)
      version = workflow.versions.create!(version_number: 1, status: "draft", definition: definition)
      workflow.publish!(version: version)

      get new_admin_whatsapp_response_flow_path(whatsapp_template_id: template.id)

      document = Nokogiri::HTML(response.body)
      expect(document.css("select[name$='[action]'] option").map(&:text)).to include("Iniciar automação")
      expect(document.css("select[name$='[automation_workflow_id]'] option").map(&:text)).to include("Conversa de teste")
      expect(document.at_css("a[href*='automacoes/new']")["href"]).to include("whatsapp_template_id=#{template.id}")
    end

    it "salva o botao com automacao e exige escolher uma" do
      workflow = admin.tenant.automation_workflows.create!(name: "Outra conversa")
      params = ->(id) { { whatsapp_response_flow: { name: "Com automação", whatsapp_template_id: template.id, active: "1",
                          button_actions: { "text:0:comprar" => { button_key: "text:0:comprar", button_text: "Comprar", action: "run_automation", automation_workflow_id: id.to_s } } } } }

      post admin_whatsapp_response_flows_path, params: params.call("")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Escolha a automação do botão Comprar")

      post admin_whatsapp_response_flows_path, params: params.call(workflow.id)
      expect(WhatsappResponseFlow.last.button_actions.dig("text:0:comprar", "automation_workflow_id")).to eq(workflow.id.to_s)
    end

    it "no novo fluxo o template e escolhido num select (so templates sem fluxo)" do
      other = admin.tenant.whatsapp_templates.create!(
        name: "menu_outro", language: "pt_BR", category: "UTILITY", status: "APPROVED", usage_context: "response_flow", waba_id: "waba-salute",
        body: "Oi", buttons: [{ "kind" => "quick_reply", "text" => "Sim" }]
      )
      admin.tenant.whatsapp_response_flows.create!(name: "Já tem", whatsapp_template: other, button_actions: {})
      template # let preguiçoso: garante o template sem fluxo

      get new_admin_whatsapp_response_flow_path

      select = Nokogiri::HTML(response.body).at_css("select[name='whatsapp_response_flow[whatsapp_template_id]']")
      expect(select).to be_present
      options = select.css("option").map(&:text)
      expect(options).to include("menu_salute")
      expect(options).not_to include("menu_outro")
      expect(select["data-action"]).to include("whatsapp-response-flow#changeTemplate")
    end

    it "abre a edicao quando o template escolhido ja tem fluxo" do
      flow = admin.tenant.whatsapp_response_flows.create!(name: "Fluxo", whatsapp_template: template, button_actions: {})

      get new_admin_whatsapp_response_flow_path(whatsapp_template_id: template.id)

      expect(response).to redirect_to(edit_admin_whatsapp_response_flow_path(flow))
    end

    it "na edicao o template aparece bloqueado e nao muda ao salvar" do
      other = admin.tenant.whatsapp_templates.create!(
        name: "menu_outro2", language: "pt_BR", category: "UTILITY", status: "APPROVED", usage_context: "response_flow", waba_id: "waba-salute",
        body: "Oi", buttons: [{ "kind" => "quick_reply", "text" => "Sim" }]
      )
      flow = admin.tenant.whatsapp_response_flows.create!(name: "Fluxo", whatsapp_template: template, button_actions: {})

      get edit_admin_whatsapp_response_flow_path(flow)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("select[name='whatsapp_response_flow[whatsapp_template_id]']")).to be_nil
      expect(document.at_css("input[readonly][value='menu_salute']")).to be_present

      patch admin_whatsapp_response_flow_path(flow), params: { whatsapp_response_flow: { name: "Renomeado", whatsapp_template_id: other.id, button_actions: {} } }

      expect(flow.reload).to have_attributes(name: "Renomeado", whatsapp_template_id: template.id)
    end
  end

  it "renderiza o componente de decisoes dos botoes para template aprovado" do
    get new_admin_whatsapp_response_flow_path(whatsapp_template_id: template.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Decisões dos botões")
    expect(response.body).to include("Comprar")
    expect(response.body).to include("Manutenções")
  end

  it "salva a acao de atendimento mapeada para um botao" do
    rule = create(:distribution_rule, tenant: admin.tenant, name: "Equipe de vendas", distribution_mode: :attendance)
    attendant = create(:admin_user, tenant: admin.tenant)
    create(:distribution_rule_agent, tenant: admin.tenant, distribution_rule: rule, admin_user: attendant)

    expect do
      post admin_whatsapp_response_flows_path, params: {
        whatsapp_response_flow: {
          name: "Fluxo Salute",
          whatsapp_template_id: template.id,
          active: "1",
          button_actions: {
            "text:0:comprar" => {
              button_key: "text:0:comprar",
              button_text: "Comprar",
              action: "distribute_lead",
              distribution_rule_id: rule.id.to_s,
              target_admin_user_id: attendant.id.to_s,
              inside_hours_message: "Só um momento, um atendente irá entrar em contato.",
              outside_hours_message: "Não estamos disponíveis no momento.",
              business_hours: {
                enabled: "1",
                days: ["mon", "tue"],
                start: "08:00",
                end: "18:00"
              }
            }
          }
        }
      }
    end.to change(WhatsappResponseFlow, :count).by(1)
      .and change(AutomationWorkflow, :count).by(1)

    flow = WhatsappResponseFlow.last
    expect(response).to redirect_to(admin_whatsapp_response_flows_path)
    expect(flow.automation_workflow.name).to eq("Fluxo Salute")
    expect(flow.automation_workflow.active_version.definition_hash.dig(:source, :kind)).to eq("whatsapp_response_flow")
    expect(flow.button_actions.dig("text:0:comprar", "action")).to eq("distribute_lead")
    expect(flow.button_actions.dig("text:0:comprar", "distribution_rule_id")).to eq(rule.id.to_s)
    expect(flow.button_actions.dig("text:0:comprar", "target_admin_user_id")).to eq(attendant.id.to_s)
  end

  it "salva varios atendentes e a acao de enviar para usuario" do
    rule = create(:distribution_rule, tenant: admin.tenant, name: "Equipe de vendas")
    agents = create_list(:admin_user, 2, tenant: admin.tenant)
    agents.each { |agent| create(:distribution_rule_agent, tenant: admin.tenant, distribution_rule: rule, admin_user: agent) }
    user = create(:admin_user, tenant: admin.tenant)

    post admin_whatsapp_response_flows_path, params: {
      whatsapp_response_flow: {
        name: "Fluxo multi", whatsapp_template_id: template.id, active: "1",
        button_actions: {
          "text:0:comprar" => { button_key: "text:0:comprar", button_text: "Comprar", action: "distribute_lead",
                                distribution_rule_id: rule.id.to_s, target_admin_user_ids: agents.map { |a| a.id.to_s } },
          "text:1:alugar" => { button_key: "text:1:alugar", button_text: "Alugar", action: "send_to_user", target_user_id: user.id.to_s }
        }
      }
    }

    flow = WhatsappResponseFlow.last
    expect(response).to redirect_to(admin_whatsapp_response_flows_path)
    expect(flow.button_actions.dig("text:0:comprar", "target_admin_user_ids")).to match_array(agents.map { |a| a.id.to_s })
    expect(flow.button_actions.dig("text:1:alugar", "target_user_id")).to eq(user.id.to_s)
  end

  it "preserva a decisao de botoes que nao vieram no formulario ao salvar" do
    flow = admin.tenant.whatsapp_response_flows.create!(
      name: "Fluxo", whatsapp_template: template,
      button_actions: {
        "text:0:comprar" => { "button_key" => "text:0:comprar", "button_text" => "Comprar", "action" => "record_only" },
        "text:9:antigo" => { "button_key" => "text:9:antigo", "button_text" => "Antigo", "action" => "send_url", "url" => "https://salute.com.br" }
      }
    )

    patch admin_whatsapp_response_flow_path(flow), params: { whatsapp_response_flow: {
      name: "Fluxo", button_actions: { "text:0:comprar" => { button_key: "text:0:comprar", button_text: "Comprar", action: "record_only" } }
    } }

    expect(flow.reload.button_actions.keys).to contain_exactly("text:0:comprar", "text:9:antigo")
    expect(flow.button_actions.dig("text:9:antigo", "url")).to eq("https://salute.com.br")
  end

  it "marca o fluxo como receptivo do numero aprovado" do
    other_sender = create(:whatsapp_sender_number, tenant: admin.tenant, waba_id: template.waba_id, label: "Suporte", display_phone_number: "5511999997777")
    sender = create(:whatsapp_sender_number, tenant: admin.tenant, waba_id: template.waba_id, label: "Vendas", display_phone_number: "5511999998888")

    post admin_whatsapp_response_flows_path, params: {
      whatsapp_sender_number_id: sender.id,
      set_as_receptive_for_sender: "1",
      whatsapp_response_flow: {
        name: "Fluxo receptivo",
        whatsapp_template_id: template.id,
        active: "1",
        button_actions: {
          "text:0:comprar" => {
            button_key: "text:0:comprar",
            button_text: "Comprar",
            action: "record_only"
          }
        }
      }
    }

    expect(response).to redirect_to(admin_whatsapp_response_flows_path)
    expect(sender.reload.receptive_response_flow).to eq(WhatsappResponseFlow.last)
    expect(other_sender.reload.receptive_response_flow).to be_nil
  end

  it "exige atendente quando a regra usa modo atendimento" do
    rule = create(:distribution_rule, tenant: admin.tenant, name: "Atendimento receptivo", distribution_mode: :attendance)

    post admin_whatsapp_response_flows_path, params: {
      whatsapp_response_flow: {
        name: "Fluxo sem atendente",
        whatsapp_template_id: template.id,
        active: "1",
        button_actions: {
          "text:0:comprar" => {
            button_key: "text:0:comprar",
            button_text: "Comprar",
            action: "distribute_lead",
            distribution_rule_id: rule.id.to_s
          }
        }
      }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Selecione um atendente")
  end

  it "renderiza os selects do formulario com o componente de autocomplete e os campos da tarefa" do
    get new_admin_whatsapp_response_flow_path(whatsapp_template_id: template.id)

    document = Nokogiri::HTML(response.body)
    selects = document.css("select[name='whatsapp_response_flow[whatsapp_template_id]'], select[name$='[distribution_rule_id]'], select[name$='[target_user_id]'], select[name$='[automation_workflow_id]'], select[name$='[task_user_id]']")
    expect(selects).not_to be_empty
    expect(selects.map { |select| select["data-controller"].to_s }).to all(include("tom-select"))
    expect(document.css("select[name$='[task_due_minutes]'] option").map(&:text)).to include("em 2 horas", "em 1 dia")
    expect(document.css("select[name$='[task_priority]'] option").map(&:text)).to include("Alta")
  end

  it "recusa um usuario de tarefa que nao e da conta" do
    other_tenant = Tenant.create!(name: "Outra #{SecureRandom.hex(3)}", slug: "outra-#{SecureRandom.hex(3)}")
    outsider = create(:admin_user, tenant: other_tenant, email: "outra-conta-#{SecureRandom.hex(4)}@salute.test")
    post admin_whatsapp_response_flows_path, params: { whatsapp_response_flow: { name: "Tarefa", whatsapp_template_id: template.id, active: "1",
      button_actions: { "text:0:comprar" => { button_key: "text:0:comprar", button_text: "Comprar", action: "create_task", task_user_id: outsider.id.to_s } } } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Selecione um usuário válido para a tarefa")
  end
end
