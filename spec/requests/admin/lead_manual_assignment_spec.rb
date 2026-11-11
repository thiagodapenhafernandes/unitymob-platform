require "rails_helper"

RSpec.describe "Atribuição manual com opções de WhatsApp e roleta", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }
  let(:broker) { create(:admin_user, tenant: tenant) }
  let(:next_broker) { create(:admin_user, tenant: tenant) }
  let(:rule) { create(:distribution_rule, tenant: tenant, notify_whatsapp: true) }
  let!(:first) { create(:distribution_rule_agent, distribution_rule: rule, admin_user: broker, position: 1) }
  let!(:second) { create(:distribution_rule_agent, distribution_rule: rule, admin_user: next_broker, position: 2) }
  let(:lead) { create(:lead, tenant: tenant, distribution_rule: rule, status: "Novo Lead") }

  before do
    host! "localhost"
    sign_in admin
    allow_any_instance_of(Lead).to receive(:route_lead)
    allow(Leads::NotificationDispatcher).to receive(:notify_reassignment)
  end

  def assign(owner = broker, options = {})
    patch admin_lead_path(lead), params: {lead: {admin_user_id: owner.id}, manual_assignment: options}
  end

  it "atribui e gira só a fila do lead; reenvio do mesmo responsável não repete efeitos" do
    2.times { assign(broker, notify_whatsapp: "1", rotate_queue: "1") }
    expect(response).to redirect_to(admin_lead_path(lead))
    expect(lead.reload).to have_attributes(admin_user_id: broker.id, status: "Novo Lead")
    expect(rule.distribution_rule_agents.order(:position).pluck(:admin_user_id)).to eq([next_broker.id, broker.id])
    expect(Leads::NotificationDispatcher).to have_received(:notify_reassignment).with(lead, broker, whatsapp: true).once
    event = lead.activities.where(kind: "assigned_directly").sole
    expect(event.metadata).to include("reason" => "manual_assignment", "queue_rotated" => true, "notify_whatsapp_requested" => true)
  end

  it "permite decidir WhatsApp e giro independentemente" do
    assign(broker, notify_whatsapp: "1")
    expect(response).to redirect_to(admin_lead_path(lead))
    expect(first.reload.position).to eq(1)
    expect(Leads::NotificationDispatcher).to have_received(:notify_reassignment).with(lead, broker, whatsapp: true)
    assign(next_broker, rotate_queue: "1")
    expect(lead.reload.admin_user_id).to eq(next_broker.id)
    expect(Leads::NotificationDispatcher).to have_received(:notify_reassignment).with(lead, next_broker, whatsapp: false)
  end

  it "mantém a atribuição antiga sem WhatsApp e sem giro quando nada é marcado" do
    assign
    expect(lead.reload.admin_user_id).to eq(broker.id)
    expect(first.reload.position).to eq(1)
    expect(first.last_lead_received_at).to be_nil
    expect(Leads::NotificationDispatcher).to have_received(:notify_reassignment).with(lead, broker, whatsapp: false)
  end

  it "não atribui nem gira quando o WhatsApp está desligado na fila" do
    rule.update!(notify_whatsapp: false)
    assign(broker, notify_whatsapp: "1", rotate_queue: "1")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("WhatsApp está desativado")
    expect(lead.reload.admin_user_id).to be_nil
    expect(first.reload.position).to eq(1)
    expect(Leads::NotificationDispatcher).not_to have_received(:notify_reassignment)
  end

  it "não ignora a elegibilidade de campanha, participantes ou check-in" do
    first.update_columns(allowed_meta_campaign_ids: ["restricted"])
    assign(broker, rotate_queue: "1")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(lead.reload.admin_user_id).to be_nil
    first.update_columns(allowed_meta_campaign_ids: [])
    rule.update!(require_active_checkin: true)
    assign(broker, rotate_queue: "1")
    expect(response).to have_http_status(:unprocessable_entity)
    outsider = create(:admin_user, tenant: tenant)
    assign(outsider, notify_whatsapp: "1")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(lead.reload.admin_user_id).to be_nil
    expect(Leads::NotificationDispatcher).not_to have_received(:notify_reassignment)
  end

  it "resolve uma fila compatível quando o lead ainda não tem fila" do
    lead.update_columns(distribution_rule_id: nil, origin: "site")
    assign(broker, rotate_queue: "1")
    expect(response).to redirect_to(admin_lead_path(lead))
    expect(lead.reload).to have_attributes(admin_user_id: broker.id, distribution_rule_id: rule.id)
  end

  it "não escolhe uma fila arbitrária nem gira fila não rotativa" do
    lead.update_columns(distribution_rule_id: nil, origin: "Facebook Lead Ads")
    assign(broker, rotate_queue: "1")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(lead.reload.admin_user_id).to be_nil
    lead.update_columns(distribution_rule_id: rule.id)
    rule.update!(distribution_mode: :shark_tank)
    assign(broker, rotate_queue: "1")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("não usa roleta rotativa")
    expect(first.reload.position).to eq(1)
  end

  it "rejeita opções inválidas e fila de outra conta" do
    assign(broker, rotate_queue: "talvez")
    expect(response).to have_http_status(:unprocessable_entity)
    other = Tenant.create!(name: "Outra", slug: "manual-other")
    foreign_rule = create(:distribution_rule, tenant: other)
    lead.update_columns(distribution_rule_id: foreign_rule.id)
    assign(broker, rotate_queue: "1")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(lead.reload.admin_user_id).to be_nil
  end

  it "bloqueia opções forjadas pelo corretor e preserva a transferência comum do próprio lead" do
    lead.update_columns(admin_user_id: broker.id)
    broker.profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    sign_out admin
    sign_in broker
    assign(next_broker, notify_whatsapp: "1", rotate_queue: "1")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(lead.reload.admin_user_id).to eq(broker.id)
    expect(Leads::NotificationDispatcher).not_to have_received(:notify_reassignment)
    assign(next_broker)
    expect(lead.reload.admin_user_id).to eq(next_broker.id)
  end

  it "renderiza os mesmos controles ax no card e nos modais, sem IDs repetidos" do
    get admin_lead_path(lead)
    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    checks = page.css('input[name="manual_assignment[rotate_queue]"]')
    expect(checks.size).to eq(3)
    expect(checks.map { |c| c['id'] }.uniq.size).to eq(3)
    expect(checks.map { |c| c['class'] }).to all(include('ax-check__input'))
    expect(checks.map { |c| c['checked'] }).to all(be_nil)
    lead.update_columns(admin_user_id: broker.id)
    sign_out admin
    sign_in broker
    get admin_lead_path(lead)
    expect(response.body).not_to include('name="manual_assignment[rotate_queue]"')
  end
  it "reverte a atribuição se a atualização da roleta falhar" do
    allow_any_instance_of(DistributionRule).to receive(:rotate_queue!).and_raise(ActiveRecord::RecordInvalid.new(first))
    assign(broker, rotate_queue: "1")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(lead.reload.admin_user_id).to be_nil
    expect(first.reload.position).to eq(1)
    expect(lead.activities.where(kind: "assigned_directly")).to be_empty
    expect(Leads::NotificationDispatcher).not_to have_received(:notify_reassignment)
  end

  it "rejeita opções malformadas sem alterar o responsável" do
    patch admin_lead_path(lead), params: {lead: {admin_user_id: broker.id}, manual_assignment: "inválido"}
    expect(response).to have_http_status(:bad_request)
    expect(lead.reload.admin_user_id).to be_nil
  end

  it "respeita modalidade, horário e arquivamento sem movimentar a fila" do
    rule.update!(business_type: :venda)
    lead.update_columns(other_information: {"business_type" => "locacao"})
    assign(broker, rotate_queue: "1")
    expect(response).to have_http_status(:unprocessable_entity)
    lead.update_columns(other_information: {"business_type" => "venda"})
    allow_any_instance_of(DistributionRule).to receive(:represamento_active?).and_return(true)
    allow_any_instance_of(DistributionRule).to receive(:outside_represamento_hours?).and_return(true)
    assign(broker, rotate_queue: "1")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("fora do horário")
    lead.update_columns(archived_at: Time.current)
    assign(broker, notify_whatsapp: "1")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(lead.reload.admin_user_id).to be_nil
    expect(first.reload.position).to eq(1)
  end

end
