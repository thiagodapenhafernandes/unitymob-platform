require "rails_helper"

RSpec.describe "Separação do atendimento WhatsApp e do comercial", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }
  let(:broker) { create(:admin_user, tenant: tenant) }
  let(:service_contact) do
    create(:lead, tenant: tenant, origin: "whatsapp", skip_automatic_routing: true,
      other_information: { "whatsapp_service_contact" => true })
  end
  let(:customer) { create(:lead, tenant: tenant, admin_user: broker, origin: "Site", skip_automatic_routing: true) }

  before do
    host! "localhost"
    sign_in admin
    Current.tenant = tenant
    allow(Whatsapp::ThreadBroadcaster).to receive(:queue_refreshed)
    allow(ActionCable.server).to receive(:broadcast)
  end

  def conversation_for(lead, phone: lead.phone)
    tenant.whatsapp_conversations.create!(lead: lead, contact_phone: phone, contact_name: lead.name)
  end

  it "mantém contatos de atendimento e funcionários fora das listagens de leads, sem apagá-los" do
    internal = create(:lead, tenant: tenant, phone: broker.phone.presence || "5547999998765", skip_automatic_routing: true)
    broker.update!(phone: internal.phone)
    service_contact
    customer
    ["list", "kanban"].each do |view|
      get admin_leads_path(view: view)
      expect(response).to have_http_status(:ok)
      expect(response.body.include?(service_contact.name)).to be(false)
      expect(response.body.include?(internal.name)).to be(false)
      expect(response.body.include?(customer.name)).to be(true)
    end
    expect(tenant.leads.where(id: [internal.id, service_contact.id]).count).to eq(2)
  end

  it "mostra atendimento na fila administrativa e permite abrir a conversa comercial pelo lead" do
    service = conversation_for(service_contact)
    commercial = conversation_for(customer)
    get admin_whatsapp_conversations_path
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("[data-conversation-id='#{service.id}']")).to be_present
    expect(document.at_css("[data-conversation-id='#{commercial.id}']")).to be_nil

    get admin_whatsapp_conversation_path(commercial, lead_id: customer.id), headers: { "Turbo-Frame" => "wa-thread" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(customer.name)
  end

  it "encaminha atendimento ao administrativo sem alterar o corretor, status ou tarefas do cliente" do
    conversation = conversation_for(customer)
    previous = customer.attributes.slice("admin_user_id", "status", "distribution_rule_id")
    task = create(:task, tenant: tenant, lead: customer, admin_user: broker)
    attendance = Whatsapp::AttendanceManager.open!(conversation: conversation, lead: customer, flow: nil,
      action: { "action" => "send_to_user", "target_user_id" => admin.id, "button_key" => "financeiro", "button_text" => "Financeiro" })

    expect(attendance.admin_user).to eq(admin)
    expect(customer.reload.attributes.slice(*previous.keys)).to eq(previous)
    expect(task.reload.admin_user).to eq(broker)
    expect(conversation.reload.assigned_admin_user).to eq(admin)
    expect(tenant.whatsapp_conversations.administrative_inbox).to include(conversation)
    expect(conversation.administrative_inbox?).to be(true)
  end

  it "abre atendimento administrativo sem precisar criar lead" do
    conversation = tenant.whatsapp_conversations.create!(contact_phone: "5547999998764", contact_name: "Fornecedor")
    expect {
      Whatsapp::AttendanceManager.open!(conversation: conversation, lead: nil, flow: nil,
        action: { "action" => "send_to_user", "target_user_id" => admin.id, "button_text" => "Administrativo" })
    }.not_to change(Lead, :count)
    expect(conversation.reload.open_attendance.admin_user).to eq(admin)
  end

  it "promove contato de atendimento ao encaminhar para um corretor" do
    conversation = conversation_for(service_contact)
    Whatsapp::AttendanceManager.open!(conversation: conversation, lead: service_contact, flow: nil,
      action: { "action" => "send_to_user", "target_user_id" => broker.id, "button_text" => "Comprar" })
    expect(service_contact.reload).not_to be_whatsapp_service_contact
    expect(service_contact.admin_user).to eq(broker)
    expect(conversation.reload.context_lead).to eq(service_contact)
    expect(conversation.administrative_inbox?).to be(false)
    expect(tenant.whatsapp_conversations.administrative_inbox).not_to include(conversation)
  end

  it "promove uma nova consulta do site sem transformar mensagens posteriores em leads novos" do
    original = service_contact
    allow(Leads::NotificationDispatcher).to receive(:deliver)
    property = create(:habitation, tenant: tenant)
    site = Leads::Intake.create!(tenant: tenant, phone: original.phone, name: original.name, origin: "Site",
      property_id: property.id, attribution_channel: "google_ads", attribution_source: "Google Ads",
      attribution_data: { "utm_source" => "google" })
    expect(site.id).to eq(original.id)
    expect(site.reload).not_to be_whatsapp_service_contact
    expect(site).to have_attributes(origin: "Site", property_id: property.id, attribution_source: "Google Ads")
    expect(site.attribution_data["utm_source"]).to eq("google")

    message = Leads::Intake.create!(tenant: tenant, phone: original.phone, name: original.name, origin: "whatsapp",
      skip_automatic_routing: true, other_information: { "whatsapp_service_contact" => true })
    expect(message.id).to eq(site.id)
    expect(message.reload).not_to be_whatsapp_service_contact
  end

  it "promove contato atribuído pela distribuição compartilhada, inclusive fora do menu WhatsApp" do
    rule = create(:distribution_rule, tenant: tenant)
    create(:distribution_rule_agent, tenant: tenant, distribution_rule: rule, admin_user: broker)
    allow(Leads::NotificationDispatcher).to receive(:deliver)
    expect(Leads::DistributorService.distribute_to_agent(service_contact, rule, broker)).to eq(rule)
    expect(service_contact.reload).not_to be_whatsapp_service_contact
    expect(service_contact.admin_user).to eq(broker)
  end

  it "não inclui conversas comerciais de outra conta na fila" do
    foreign = Tenant.create!(name: "Outra conta", slug: "other-separation-#{SecureRandom.hex(4)}")
    external = foreign.whatsapp_conversations.create!(contact_phone: "5547999998763", contact_name: "Contato de outra conta")
    get admin_whatsapp_conversations_path
    expect(Nokogiri::HTML(response.body).at_css("[data-conversation-id='#{external.id}']")).to be_nil
  end
end
