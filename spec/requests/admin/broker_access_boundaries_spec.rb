require "rails_helper"

RSpec.describe "Limites de acesso do corretor", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:tenant) { Tenant.default }
  let(:profile) { tenant.profiles.find_by!(key: "agent") }
  let(:broker) { create(:admin_user, tenant: tenant, profile: profile) }
  let(:peer) { create(:admin_user, tenant: tenant, profile: profile) }
  let(:lead) { create(:lead, tenant: tenant, admin_user: broker) }
  let(:peer_lead) { Current.set(tenant: tenant) { create(:lead, tenant: tenant, admin_user: peer) } }

  before do
    Current.tenant = tenant
    profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    host! "localhost"
    sign_in broker
  end

  def revoke(resource, action)
    permissions = profile.permissions.deep_dup
    permissions.fetch(resource)[action] = false
    profile.update!(permissions: permissions)
  end

  it "mantém os menus operacionais e oculta administração e sincronização do WhatsApp" do
    get admin_whatsapp_conversations_path
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("a[href='#{admin_tasks_path}']")).to be_present
    expect(document.at_css("a[href='#{admin_appointments_path}']")).to be_present
    expect(document.at_css("a[href='#{admin_commercial_contract_proposals_path}']")).to be_nil
    expect(document.at_css("a[href='#{edit_admin_whatsapp_service_setting_path}']")).to be_nil
    expect(document.at_css("form[action='#{sync_templates_admin_whatsapp_conversations_path}']")).to be_nil
  end

  it "bloqueia configuração e contratos por URL direta" do
    get edit_admin_whatsapp_service_setting_path
    expect(response).to redirect_to(admin_root_path)
    get admin_commercial_contract_proposals_path
    expect(response).to redirect_to(admin_root_path)
    expect(WhatsappBusinessIntegration).not_to receive(:current)
    patch admin_whatsapp_service_setting_path, params: { whatsapp_business_integration: { presentation_enabled: false } }
    expect(response).to redirect_to(admin_root_path)
  end

  it "bloqueia sincronização sem enfileirar trabalho e preserva o administrador" do
    expect(Whatsapp::SyncTemplatesJob).not_to receive(:perform_later)
    post sync_templates_admin_whatsapp_conversations_path
    expect(response).to redirect_to(admin_root_path)
  end

  it "permite ao administrador acessar contratos e sincronizar modelos" do
    sign_in create(:admin_user, :admin, tenant: tenant)
    get admin_commercial_contract_proposals_path
    expect(response).to have_http_status(:ok)
    expect(Whatsapp::SyncTemplatesJob).to receive(:perform_later).with(tenant.id)
    post sync_templates_admin_whatsapp_conversations_path
    expect(response).to redirect_to(admin_whatsapp_conversations_path)
  end

  it "interrompe ações comerciais negadas antes de qualquer alteração" do
    lead
    revoke("comercial", "manage")
    original_status = lead.status
    %i[close_deal archive schedule_activity].each do |action|
      expect {
        post public_send("#{action}_admin_lead_path", lead),
             params: { activity_kind: "return", due_at: 1.day.from_now }, as: :json
      }.not_to change(LeadActivity, :count)
      expect(response).to have_http_status(:forbidden)
      expect(lead.reload.status).to eq(original_status)
    end
  end

  it "interrompe ativação WhatsApp negada antes de consultar integração ou enviar" do
    lead
    revoke("whatsapp_inbox", "manage")
    expect(WhatsappBusinessIntegration).not_to receive(:current)
    expect(Whatsapp::SendMessageJob).not_to receive(:dispatch)
    post activate_whatsapp_template_admin_lead_path(lead), as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "permite criar proposta própria e bloqueia proposta de outro corretor" do
    post admin_lead_proposals_path(lead), params: { proposal: { title: "Própria", valor: "1000" } }
    expect(response).to redirect_to(admin_lead_path(lead))
    proposal = peer_lead.proposals.create!(admin_user: peer, valor_cents: 1000)
    get edit_admin_proposal_path(proposal)
    expect(response).to have_http_status(:not_found)
    patch admin_proposal_path(proposal), params: { proposal: { title: "Invadida" } }
    expect(response).to have_http_status(:not_found)
    delete admin_proposal_path(proposal)
    expect(response).to have_http_status(:not_found)
    expect(proposal.reload.title).not_to eq("Invadida")
    post admin_lead_proposals_path(peer_lead), params: { proposal: { valor: "1000" } }
    expect(response).to have_http_status(:not_found)
  end

  it "rejeita imóvel de outra conta na proposta" do
    other_tenant = Tenant.create!(name: "Outra #{SecureRandom.hex(4)}", slug: "outra-#{SecureRandom.hex(4)}")
    other_owner = create(:admin_user, :admin, tenant: other_tenant)
    property = create(:habitation, tenant: other_tenant, admin_user: other_owner)
    Current.tenant = tenant
    expect {
      post admin_lead_proposals_path(lead), params: { proposal: { valor: "1000", habitation_id: property.id } }
    }.not_to change(Proposal, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "mantém tarefas próprias e rejeita vínculo com lead de outro corretor" do
    post admin_tasks_path, params: { task: { title: "Própria", lead_id: lead.id } }
    task = tenant.tasks.find_by!(title: "Própria", admin_user: broker)
    post admin_tasks_path, params: { task: { title: "Alheia", lead_id: peer_lead.id } }
    expect(response).to have_http_status(:not_found)
    patch admin_task_path(task), params: { task: { lead_id: peer_lead.id } }
    expect(response).to have_http_status(:not_found)
    expect(task.reload.lead_id).to eq(lead.id)
  end

  it "mantém agenda própria e rejeita vínculo com lead de outro corretor" do
    post admin_appointments_path, params: { appointment: { title: "Própria", lead_id: lead.id, starts_at: 1.day.from_now } }
    appointment = tenant.appointments.find_by!(title: "Própria", admin_user: broker)
    post admin_appointments_path, params: { appointment: { title: "Alheia", lead_id: peer_lead.id, starts_at: 1.day.from_now } }
    expect(response).to have_http_status(:not_found)
    patch admin_appointment_path(appointment), params: { appointment: { lead_id: peer_lead.id } }
    expect(response).to have_http_status(:not_found)
    expect(appointment.reload.lead_id).to eq(lead.id)
  end

  it "nega atualização rápida de proprietário sem vínculo e permite o da própria captação" do
    proprietor = create(:proprietor, tenant: tenant, city: "Itajaí")
    patch quick_update_admin_proprietor_path(proprietor), params: { proprietor: { city: "Outra" } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(proprietor.reload.city).to eq("Itajaí")
    create(:habitation, :broker_intake, tenant: tenant, admin_user: broker, proprietor: proprietor)
    patch quick_update_admin_proprietor_path(proprietor), params: { proprietor: { city: "Outra" } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(proprietor.reload.city).to eq("Outra")
  end

  it "respeita edição revogada para etiquetas e interesses" do
    lead
    revoke("leads", "edit")
    expect {
      post admin_lead_lead_labels_path(lead), params: { lead_label: { name: "Teste", color: "blue" } }, as: :json
    }.not_to change(LeadLabel, :count)
    expect(response).to have_http_status(:forbidden)
    post admin_lead_property_interests_path(lead), params: { habitation_id: 1 }, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "respeita gerenciamento revogado para cartões pessoais" do
    revoke("whatsapp_inbox", "manage")
    expect {
      post admin_presentation_cards_path, params: { presentation_card: { label: "Meu cartão", greeting: "Olá" } }, as: :json
    }.not_to change(PresentationCard, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it "respeita publicação revogada mesmo sendo o captador responsável" do
    intake = create(:habitation, :broker_intake, tenant: tenant, admin_user: broker, intake_status: "admin_approved", exibir_no_site_flag: false)
    revoke("captacoes", "publish")
    post release_to_site_admin_captacao_path(intake)
    expect(intake.reload.exibir_no_site_flag).to be(false)
    expect(flash[:alert]).to be_present
  end
  it "preserva acesso do gestor à equipe sem abrir propostas de fora da equipe" do
    manager_profile = Profile.create!(tenant: tenant, name: "Gestor auditoria", axis: "vertical", position: 730,
                                      permissions: Profile.default_permissions_for("Gerente"))
    manager = create(:admin_user, tenant: tenant, profile: manager_profile)
    broker.update!(manager: manager)
    own_proposal = lead.proposals.create!(admin_user: broker, valor_cents: 1000)
    outside_proposal = peer_lead.proposals.create!(admin_user: peer, valor_cents: 1000)
    sign_in manager
    get edit_admin_proposal_path(own_proposal)
    expect(response).to have_http_status(:ok)
    get edit_admin_proposal_path(outside_proposal)
    expect(response).to have_http_status(:not_found)
  end

  it "permite somente ao dono da conta salvar configurações de atendimento" do
    integration = WhatsappBusinessIntegration.create!(tenant: tenant, access_token: "test-token", phone_number_id: "test-number")
    patch admin_whatsapp_service_setting_path, params: { whatsapp_business_integration: { presentation_enabled: false } }
    expect(response).to redirect_to(admin_root_path)
    original = integration.reload.presentation_enabled
    sign_in create(:admin_user, :admin, tenant: tenant)
    patch admin_whatsapp_service_setting_path, params: { whatsapp_business_integration: { presentation_enabled: !original } }
    expect(response).to redirect_to(edit_admin_whatsapp_service_setting_path)
    expect(integration.reload.presentation_enabled).to eq(!original)
  end

  it "transfere tarefa com o lead e bloqueia o responsável anterior" do
    task = Task.create!(tenant: tenant, admin_user: broker, lead: lead, title: "Retornar")
    lead.update!(admin_user: peer)
    patch complete_admin_task_path(task), as: :json
    expect(response).to have_http_status(:not_found)
    expect(task.reload.admin_user_id).to eq(peer.id)
    expect(task.status).to eq("pendente")
    sign_in peer
    patch admin_task_path(task), params: { task: { title: "Retornar amanhã", lead_id: lead.id } }
    expect(task.reload.title).to eq("Retornar amanhã")
    patch complete_admin_task_path(task), as: :json
    expect(response).to have_http_status(:ok)
    expect(task.reload.status).to eq("concluida")
  end

  it "transfere agenda com o lead e bloqueia o responsável anterior" do
    appointment = Appointment.create!(tenant: tenant, admin_user: broker, lead: lead, title: "Visita", starts_at: 1.day.ago)
    lead.update!(admin_user: peer)
    patch admin_appointment_path(appointment), params: { appointment: { title: "Indevida" } }
    expect(response).to have_http_status(:not_found)
    expect(appointment.reload.admin_user_id).to eq(peer.id)
    sign_in peer
    patch admin_appointment_path(appointment), params: { appointment: { title: "Visita reagendada", lead_id: lead.id } }
    expect(appointment.reload.title).to eq("Visita reagendada")
  end

  it "não permite operar tarefa ou compromisso atribuídos a outro corretor" do
    task = Task.create!(tenant: tenant, admin_user: peer, lead: peer_lead, title: "Alheia")
    appointment = Appointment.create!(tenant: tenant, admin_user: peer, lead: peer_lead, title: "Alheio", starts_at: 1.day.from_now)
    patch complete_admin_task_path(task), as: :json
    expect(response).to have_http_status(:not_found)
    sign_in broker
    delete admin_task_path(task)
    expect(response).to have_http_status(:not_found)
    sign_in broker
    delete admin_appointment_path(appointment)
    expect(response).to have_http_status(:not_found)
    expect(task.reload.status).to eq("pendente")
    expect(Appointment.exists?(appointment.id)).to be(true)
  end

  it "completa proprietário antes do vínculo usando o contexto real do formulário" do
    proprietor = create(:proprietor, tenant: tenant, city: nil, email: "original@example.com", phone_primary: "5547999998877")
    intake = create(:habitation, :broker_intake, tenant: tenant, admin_user: broker, proprietor: nil)
    get edit_admin_captacao_path(intake, step: "proprietario")
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    template = document.at_css("[data-habitation-owner-selector-update-url-template-value]")["data-habitation-owner-selector-update-url-template-value"]
    expect(template).to include("habitation_id=#{intake.id}")
    original_name = proprietor.name
    patch template.sub(":id", proprietor.id.to_s), params: { proprietor: { city: "Itajaí", email: "changed@example.com", name: "Alterado", phone_primary: "5547999991111" } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(proprietor.reload.city).to eq("Itajaí")
    expect(proprietor.email).to eq("original@example.com")
    expect(proprietor.name).to eq(original_name)
    expect(proprietor.phone_primary).to eq("5547999998877")
    expect(intake.reload.proprietor_id).to be_nil
  end

  it "rejeita contexto de captação alheia ou pendente de revisão" do
    proprietor = create(:proprietor, tenant: tenant, city: nil)
    outside = create(:habitation, :broker_intake, tenant: tenant, admin_user: peer)
    pending = create(:habitation, :broker_intake, tenant: tenant, admin_user: broker, intake_status: "submitted_for_admin_review")
    [outside, pending].each do |intake|
      patch quick_update_admin_proprietor_path(proprietor, habitation_id: intake.id), params: { proprietor: { city: "Alterada" } }, as: :json
      expect(response).to have_http_status(:not_found)
      expect(proprietor.reload.city).to be_nil
    end
  end
  it "não aceita contexto nem proprietário de outra conta na complementação" do
    proprietor = create(:proprietor, tenant: tenant, city: nil)
    intake = create(:habitation, :broker_intake, tenant: tenant, admin_user: broker)
    other_tenant = Tenant.create!(name: "Outra #{SecureRandom.hex(4)}", slug: "outra-#{SecureRandom.hex(4)}")
    other_user = create(:admin_user, :admin, tenant: other_tenant)
    other_property = create(:habitation, :broker_intake, tenant: other_tenant, admin_user: other_user)
    other_proprietor = create(:proprietor, tenant: other_tenant, city: nil)
    Current.tenant = tenant
    patch quick_update_admin_proprietor_path(proprietor, habitation_id: other_property.id), params: { proprietor: { city: "Alterada" } }, as: :json
    expect(response).to have_http_status(:not_found)
    patch quick_update_admin_proprietor_path(other_proprietor, habitation_id: intake.id), params: { proprietor: { city: "Alterada" } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(proprietor.reload.city).to be_nil
    expect(other_proprietor.reload.city).to be_nil
  end

end
