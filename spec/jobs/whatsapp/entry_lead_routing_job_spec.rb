require "rails_helper"

RSpec.describe Whatsapp::EntryLeadRoutingJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers
  let(:tenant) { Tenant.default }
  let(:agent) { create(:admin_user, tenant: tenant) }
  let(:rule) { create(:distribution_rule, tenant: tenant, business_type: :venda,
    custom_filters: [{key: "meta_campaign_id", value: "120250339532760049"}]) }
  let(:lead) { create(:lead, tenant: tenant, origin: "whatsapp", other_information: {
    "whatsapp_service_contact" => true, "meta_campaign_id" => "120250339532760049",
    "meta_enriched_at" => Time.current.iso8601, "whatsapp_entry" => {"message_id" => "wamid.entry"}
  }) }
  let(:conversation) { WhatsappConversation.create!(tenant: tenant, lead: lead, contact_phone: lead.phone, status: "open") }
  let(:message) { conversation.messages.create!(tenant: tenant, wa_message_id: "wamid.entry", direction: "inbound",
    msg_type: "text", body: "Quero comprar um apartamento", status: "delivered", referral: {"source_type" => "ad", "source_id" => "987654"}) }

  before do
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent)
    allow(Leads::NotificationDispatcher).to receive(:deliver)
    allow(Automation::Dispatcher).to receive(:dispatch)
  end

  def perform
    described_class.perform_now(tenant.id, lead.id, message.id)
  end

  it "promove somente a campanha configurada e distribui uma única vez" do
    original = lead.other_information.deep_dup
    2.times { perform }
    expect(lead.reload.admin_user_id).to eq(agent.id)
    expect(lead.distribution_rule_id).to eq(rule.id)
    expect(lead.whatsapp_service_contact?).to be(false)
    expect(lead.origin).to eq("whatsapp")
    expect(lead.other_information).to include(original.except("whatsapp_service_contact"))
    expect(lead.activities.where(kind: "distributed").count).to eq(1)
    expect(Leads::NotificationDispatcher).to have_received(:deliver).once
  end

  it "mantém comercial o lead represado para distribuição posterior" do
    schedule = DistributionRule::DAYS.index_with { {"active" => "false", "start" => "09:00", "end" => "18:00"} }
    schedule["fri"]["active"] = "true"
    rule.update!(represamento_active: true, represamento_schedule: schedule)
    travel_to(Time.zone.local(2026, 6, 26, 8)) { perform }
    expect(lead.reload.whatsapp_service_contact?).to be(false)
    expect(lead.status).to eq("Represado")
    expect(lead.distribution_rule_id).to eq(rule.id)
  end

  it "não usa regra genérica de locação para contato administrativo" do
    rule.update!(custom_filters: [], business_type: :locacao)
    message.update!(body: "Preciso falar com o financeiro sobre meu boleto")
    perform
    expect(lead.reload.whatsapp_service_contact?).to be(true)
    expect(lead.admin_user_id).to be_nil
    expect(Leads::NotificationDispatcher).not_to have_received(:deliver)
  end

  it "não promove fila de atendimento administrativo" do
    rule.update!(distribution_mode: :attendance)
    perform
    expect(lead.reload.whatsapp_service_contact?).to be(true)
    expect(Leads::NotificationDispatcher).not_to have_received(:deliver)
  end

  it "não aceita correspondência parcial do ID de campanha" do
    rule.update!(custom_filters: [{key: "meta_campaign_id", value: "120250339"}])
    perform
    expect(lead.reload.admin_user_id).to be_nil
  end

  it "não escolhe entre dois destinos explícitos da mesma campanha" do
    create(:distribution_rule, tenant: tenant, business_type: :venda, custom_filters: rule.custom_filters)
    perform
    expect(lead.reload.whatsapp_service_contact?).to be(true)
    expect(lead.admin_user_id).to be_nil
  end

  it "distribui consulta comercial sem anúncio ou filtro de campanha" do
    rule.update!(custom_filters: [])
    message.update!(referral: {})
    perform
    expect(lead.reload.admin_user_id).to eq(agent.id)
  end

  it "não altera cadastro comercial histórico já atribuído" do
    lead.update_columns(other_information: lead.other_information.except("whatsapp_service_contact"), admin_user_id: agent.id)
    original = lead.reload.attributes
    perform
    expect(lead.reload.attributes).to eq(original)
    expect(Leads::NotificationDispatcher).not_to have_received(:deliver)
  end

  it "não promove outra mensagem da conversa" do
    message.update!(wa_message_id: "wamid.other")
    perform
    expect(lead.reload.whatsapp_service_contact?).to be(true)
  end

  it "classifica a modalidade sem depender de integração Meta" do
    rule.update!(custom_filters: [])
    lead.update_columns(other_information: lead.other_information.except("meta_enriched_at", "meta_campaign_id"))
    perform
    expect(lead.reload.admin_user_id).to eq(agent.id)
  end

  it "não deduz venda do nome da campanha nem da fila" do
    rule.update!(custom_filters: [])
    message.update!(body: "Olá, tenho interesse")
    lead.update_columns(other_information: lead.other_information.merge("meta_campaign_name" => "Venda Gralha Azul"))
    perform
    expect(lead.reload.admin_user_id).to be_nil
  end

  it "seleciona locação antes do filtro opcional de campanha" do
    rental_agent = create(:admin_user, tenant: tenant)
    rental_rule = create(:distribution_rule, tenant: tenant, business_type: :locacao)
    create(:distribution_rule_agent, distribution_rule: rental_rule, admin_user: rental_agent)
    message.update!(body: "Quero alugar apartamento")
    perform
    expect(lead.reload.admin_user_id).to eq(rental_agent.id)
    expect(lead.distribution_rule_id).to eq(rental_rule.id)
  end

  it "preserva o atendimento administrativo já aberto mesmo com texto comercial" do
    administrative_rule = create(:distribution_rule, tenant: tenant, distribution_mode: :attendance)
    conversation.attendances.create!(tenant: tenant, distribution_rule: administrative_rule, status: "open", opened_at: Time.current)
    perform
    expect(lead.reload.whatsapp_service_contact?).to be(true)
    expect(lead.admin_user_id).to be_nil
    expect(Leads::NotificationDispatcher).not_to have_received(:deliver)
  end

  it "não usa regra inativa nem de outra conta" do
    rule.update!(active: false)
    other = Tenant.create!(name: "Outra conta", slug: "campaign-other-rule")
    create(:distribution_rule, tenant: other, custom_filters: rule.custom_filters)
    perform
    expect(lead.reload.admin_user_id).to be_nil
  end

  it "não acessa mensagens ou leads de outra conta" do
    other = Tenant.create!(name: "Outra conta", slug: "campaign-other")
    described_class.perform_now(other.id, lead.id, message.id)
    expect(lead.reload.admin_user_id).to be_nil
    expect(Leads::NotificationDispatcher).not_to have_received(:deliver)
  end
end
