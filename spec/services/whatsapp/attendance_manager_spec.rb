require "rails_helper"

RSpec.describe Whatsapp::AttendanceManager do
  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  let(:tenant) { Tenant.default }
  let(:rule) { create(:distribution_rule, tenant: tenant) }
  let(:agent_a) { create(:admin_user, tenant: tenant) }
  let(:agent_b) { create(:admin_user, tenant: tenant) }
  let(:template) do
    tenant.whatsapp_templates.create!(
      name: "menu_atendimento", language: "pt_BR", status: "APPROVED", usage_context: "response_flow",
      waba_id: "waba-att", category: "UTILITY", body: "Como podemos ajudar?",
      buttons: { "0" => { "kind" => "quick_reply", "text" => "Comprar" }, "1" => { "kind" => "quick_reply", "text" => "Alugar" } }
    )
  end
  let(:buy) { template.interactive_buttons.first }
  let(:rent) { template.interactive_buttons.second }
  let!(:flow) do
    create(:distribution_rule_agent, tenant: tenant, distribution_rule: rule, admin_user: agent_a, position: 1)
    create(:distribution_rule_agent, tenant: tenant, distribution_rule: rule, admin_user: agent_b, position: 2)
    actions = [buy, rent].to_h do |button|
      [button["key"], { "button_key" => button["key"], "button_text" => button["text"], "action" => "distribute_lead",
                        "distribution_rule_id" => rule.id, "target_admin_user_ids" => [agent_a.id, agent_b.id],
                        "finish_message" => "Até logo!", "inside_hours_message" => "Já vamos atender.", "business_hours" => { "enabled" => "0" } }]
    end
    tenant.whatsapp_response_flows.create!(name: "Menu", whatsapp_template: template, button_actions: actions)
  end
  let(:conversation) { tenant.whatsapp_conversations.create!(contact_phone: "5547999990000", contact_name: "Maria") }

  before do
    allow(Whatsapp::SendMessageJob).to receive(:dispatch)
    allow(Whatsapp::ThreadBroadcaster).to receive(:message_created)
    allow(ActionCable.server).to receive(:broadcast)
    allow(Whatsapp::ThreadBroadcaster).to receive(:queue_refreshed)
  end

  def click(button)
    conversation.messages.create!(direction: "outbound", msg_type: "template", template_name: template.name, body: template.body, status: "sent", wa_message_id: "wamid.#{SecureRandom.hex(4)}")
    inbound = conversation.messages.create!(direction: "inbound", msg_type: "button", body: button["text"], status: "delivered")
    Whatsapp::ResponseFlowRunner.call(
      conversation: conversation, inbound_message: inbound,
      raw_message: { type: "button", button: { text: button["text"], payload: button["key"] } },
      phone_number_id: nil
    )
    conversation.reload
  end

  def click_interactive(id, title)
    inbound = conversation.messages.create!(direction: "inbound", msg_type: "interactive", body: title, status: "delivered")
    Whatsapp::ResponseFlowRunner.call(
      conversation: conversation, inbound_message: inbound,
      raw_message: { type: "interactive", interactive: { button_reply: { id: id, title: title } } }
    )
    conversation.reload
  end

  def write(text, phone_number_id: nil)
    inbound = conversation.messages.create!(direction: "inbound", msg_type: "text", body: text, status: "delivered")
    Whatsapp::ResponseFlowRunner.call(conversation: conversation, inbound_message: inbound, raw_message: { type: "text", text: { body: text } }, phone_number_id: phone_number_id)
    conversation.reload
  end

  it "abre o atendimento, prende ao dono e notifica em tempo real" do
    click(buy)

    attendance = conversation.open_attendance
    expect(attendance).to be_present
    expect(attendance.admin_user).to eq(agent_a).or eq(agent_b)
    expect(conversation.assigned_admin_user).to eq(attendance.admin_user)
    notification = InAppNotification.find_by(admin_user: attendance.admin_user)
    expect(notification.title).to eq("Novo atendimento")
    expect(notification.url).to eq("/admin/atendimento/whatsapp/#{conversation.id}")
  end

  it "registra na timeline quando nao ha atendente elegivel" do
    agent_a.update_columns(active: false)
    agent_b.update_columns(active: false)

    click(buy)

    expect(conversation.open_attendance).to be_nil
    expect(LeadActivity.where(lead: conversation.lead, kind: "whatsapp_attendance_unassigned").first.metadata["reason"]).to eq("no_eligible_agent")
  end

  it "mantem um unico atendimento e pede confirmacao ao clicar em outro botao" do
    click(buy)
    attendance = conversation.open_attendance

    click(rent)

    expect(conversation.attendances.count).to eq(1)
    expect(attendance.reload.pending_switch["button_text"]).to eq("Alugar")
    ask = conversation.messages.outbound.where(msg_type: "interactive").last
    expect(ask.template_components.map { |b| b["title"] }).to eq(%w[Sim Não])
    expect(InAppNotification.where(admin_user: attendance.admin_user, title: "Cliente quer trocar de assunto")).to exist
  end

  it "troca de atendimento quando o cliente confirma" do
    click(buy)
    first = conversation.open_attendance
    click(rent)

    click_interactive("attsw:yes:#{first.id}", "Sim")

    expect(first.reload.status).to eq("closed")
    expect(first.close_reason).to eq("switched_by_customer")
    expect(conversation.open_attendance.button_text).to eq("Alugar")
  end

  it "mantem o atendimento quando o cliente recusa" do
    click(buy)
    first = conversation.open_attendance
    click(rent)

    click_interactive("attsw:no:#{first.id}", "Não")

    expect(first.reload).to be_open
    expect(first.pending_switch).to eq({})
    expect(conversation.messages.outbound.last.body).to include("Seguimos com o seu atendimento atual")
  end

  it "finaliza com a mensagem pronta e reenvia o menu quando o cliente escreve depois" do
    click(buy)
    attendance = conversation.open_attendance
    allow(Whatsapp::ServiceWindowGuard).to receive(:call).and_return(double(locked?: false))

    result = described_class.finish!(attendance, admin_user: attendance.admin_user)

    expect(result.warning).to be_nil
    expect(attendance.reload.status).to eq("closed")
    expect(conversation.messages.outbound.where(body: "Até logo!")).to exist
    expect(LeadActivity.where(lead: conversation.lead, kind: "whatsapp_attendance_finished")).to exist

    write("oi, voltei")

    expect(conversation.messages.outbound.where(msg_type: "template", template_name: template.name).count).to eq(2)
  end

  context "primeiro contato no numero receptivo" do
    let!(:sender) { create(:whatsapp_sender_number, tenant: tenant, waba_id: template.waba_id, phone_number_id: "phone-menu", receptive_response_flow: flow) }

    it "devolve o menu quando o contato escreve sem nenhum atendimento anterior" do
      write("oi", phone_number_id: "phone-menu")

      menu = conversation.messages.outbound.where(msg_type: "template", template_name: template.name)
      expect(menu.count).to eq(1)
      write("oi de novo", phone_number_id: "phone-menu")
      expect(menu.count).to eq(1) # cooldown
    end

    it "nao interrompe uma conversa em andamento com atendente humano" do
      conversation.messages.create!(direction: "outbound", msg_type: "text", body: "Oi, sou o corretor", status: "sent", admin_user: agent_a)

      write("oi", phone_number_id: "phone-menu")

      expect(conversation.messages.outbound.where(msg_type: "template")).to be_empty
    end
  end

  it "nao reenvia o menu enquanto ha atendimento aberto" do
    click(buy)
    before = conversation.messages.outbound.count

    write("oi")

    expect(conversation.messages.outbound.count).to eq(before)
  end

  it "passa o atendimento para outro do pool quando o dono fica indisponivel" do
    click(buy)
    attendance = conversation.open_attendance
    owner = attendance.admin_user
    owner.update_columns(active: false)

    write("alguem ai?")

    expect(attendance.reload.admin_user).not_to eq(owner)
    expect(LeadActivity.where(lead: conversation.lead, kind: "whatsapp_attendance_transferred")).to exist
  end

  describe "transferencia manual e tempo real" do
    it "transfere para um colega do grupo do botao, avisa os dois lados e registra quem transferiu" do
      click(buy)
      attendance = conversation.open_attendance
      from = attendance.admin_user
      to = [agent_a, agent_b].find { |agent| agent != from }
      by = create(:admin_user, tenant: tenant)

      described_class.transfer!(attendance, to: to, by: by)

      expect(attendance.reload.admin_user).to eq(to)
      expect(attendance.accepted_at).to be_nil
      expect(conversation.reload.assigned_admin_user).to eq(to)
      expect(InAppNotification.find_by(admin_user: to, title: "Atendimento transferido para você").body).to include("por #{by.name}")
      expect(InAppNotification.where(admin_user: from, title: "Atendimento transferido")).to exist
      expect(LeadActivity.where(lead: conversation.lead, kind: "whatsapp_attendance_transferred").last.metadata).to include("reason" => "manual", "by" => by.name)
    end

    it "recusa transferir para quem esta fora do grupo do botao" do
      click(buy)
      attendance = conversation.open_attendance
      outsider = create(:admin_user, tenant: tenant)
      create(:distribution_rule_agent, tenant: tenant, distribution_rule: rule, admin_user: outsider, position: 9)

      expect(described_class.transfer!(attendance, to: outsider, by: agent_a)).to be_nil
      expect(attendance.reload.admin_user).not_to eq(outsider)
    end

    it "avisa em tempo real quem participa e quem gerencia, e diz a quem a conversa deixou de ser visivel" do
      click(buy)
      attendance = conversation.open_attendance
      from = attendance.admin_user
      to = [agent_a, agent_b].find { |agent| agent != from }
      sent = []
      allow(InAppNotification).to receive(:broadcast_event!) { |user_id, payload| sent << [user_id, payload] }

      described_class.transfer!(attendance, to: to, by: from)

      by_user = sent.select { |_id, payload| payload[:event] == "attendance_changed" }.to_h
      expect(by_user[to.id]).to include(visible: true, conversation_id: conversation.id)
      expect(by_user[to.id][:html]).to include("wa-inbox-conversation")
      expect(by_user[from.id]).to include(visible: false, html: nil)
    end
  end

  it "avisa quem perdeu o atendimento quando ele e transferido" do
    click(buy)
    attendance = conversation.open_attendance
    previous = attendance.admin_user

    write("alguem?") if previous.update_columns(active: false)

    expect(InAppNotification.where(admin_user: previous, title: "Atendimento transferido")).to exist
  end

  it "avisa o dono quando o cliente inicia outro assunto e o atendimento antigo fecha" do
    click(buy)
    first = conversation.open_attendance
    owner = first.admin_user
    click(rent)

    click_interactive("attsw:yes:#{first.id}", "Sim")

    expect(InAppNotification.where(admin_user: owner, title: "Atendimento encerrado")).to exist
  end

  it "avisa o dono quando outra pessoa finaliza o atendimento" do
    click(buy)
    attendance = conversation.open_attendance
    manager = create(:admin_user, tenant: tenant)
    allow(Whatsapp::ServiceWindowGuard).to receive(:call).and_return(double(locked?: false))

    described_class.finish!(attendance, admin_user: manager)

    expect(InAppNotification.where(admin_user: attendance.admin_user, title: "Atendimento finalizado por #{manager.name}")).to exist
    expect(attendance.reload.close_reason_label).to eq("Finalizado por #{manager.name}")
  end

  it "encerra pela janela de 24h do WhatsApp quando o cliente nao responde" do
    click(buy)
    attendance = conversation.open_attendance
    conversation.messages.inbound.update_all(created_at: 25.hours.ago)

    Whatsapp::AttendanceWindowSweepJob.perform_now

    expect(attendance.reload).to have_attributes(status: "closed", close_reason: "window_expired")
    expect(InAppNotification.where(admin_user: attendance.admin_user, title: "Atendimento encerrado")).to exist
  end

  it "mantem aberto o atendimento com mensagem do cliente dentro das 24h" do
    click(buy)
    attendance = conversation.open_attendance
    conversation.messages.inbound.update_all(created_at: 23.hours.ago)

    Whatsapp::AttendanceWindowSweepJob.perform_now

    expect(attendance.reload).to be_open
  end

  it "nao alerta ninguem por mensagem de cliente com atendimento ja encerrado" do
    click(buy)
    attendance = conversation.open_attendance
    expect(conversation.alert_recipient_id).to eq(attendance.admin_user_id)

    described_class.close!(attendance, reason: "finished")

    expect(conversation.reload.alert_recipient_id).to be_nil
  end

  it "nao agenda repasse por conta do bolsao (pocket) da regra" do
    rule.update_columns(pocket_active: true, pocket_time: 5)
    expect(Whatsapp::AttendanceAcceptanceJob).not_to receive(:set)

    click(buy)
  end

  it "agenda o repasse pelo prazo configurado no proprio botao" do
    flow.update!(button_actions: flow.button_actions.deep_merge(buy["key"] => { "accept_timeout_minutes" => 12 }))
    expect(Whatsapp::AttendanceAcceptanceJob).to receive(:set).with(wait: 12.minutes).and_return(double(perform_later: true))

    click(buy)
  end

  it "transfere quando o dono nao aceita dentro do pocket" do
    click(buy)
    attendance = conversation.open_attendance
    owner = attendance.admin_user

    Whatsapp::AttendanceAcceptanceJob.perform_now(attendance.id, owner.id, tenant_id: tenant.id)

    expect(attendance.reload.admin_user).not_to eq(owner)
  end

  it "nao transfere quando o dono ja aceitou" do
    click(buy)
    attendance = conversation.open_attendance
    described_class.accept!(conversation, attendance.admin_user)

    Whatsapp::AttendanceAcceptanceJob.perform_now(attendance.id, attendance.admin_user_id, tenant_id: tenant.id)

    expect(attendance.reload.admin_user).to eq(attendance.admin_user)
    expect(attendance).to be_accepted
  end
end
