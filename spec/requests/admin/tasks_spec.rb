require "rails_helper"

RSpec.describe "Admin::Tasks", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "tasks-#{SecureRandom.hex(6)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  describe "GET /admin/tasks" do
    it "lista tarefas pendentes do usuário" do
      create(:lead, name: "Cliente Tarefa", phone: "11999999999")
      Task.create!(title: "Ligar para cliente", admin_user: admin, status: "pendente")

      get admin_tasks_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Minhas Tarefas")
      expect(response.body).to include("Ligar para cliente")
    end
  end

  describe "POST /admin/tasks" do
    it "cria tarefa e registra atividade no lead" do
      lead = create(:lead)

      expect {
        post admin_tasks_path, params: { task: { title: "Enviar proposta", kind: "follow_up", lead_id: lead.id } }
      }.to change(Task, :count).by(1)
       .and change { lead.activities.where(kind: "task_created").count }.by(1)

      expect(response).to have_http_status(:redirect)
      expect(Task.last.created_by_id).to eq(admin.id)
    end

    it "não permite atribuir tarefa para usuário fora da subárvore do gestor" do
      tenant = Tenant.create!(name: "Tenant tarefas #{SecureRandom.hex(3)}", slug: "tenant-tarefas-#{SecureRandom.hex(3)}")
      owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
      manager_profile = Profile.create!(
        tenant: tenant,
        name: "Manager Comercial",
        axis: "vertical",
        position: 300,
        permissions: {
          "dashboard" => { "view" => true },
          "comercial" => { "view" => true, "manage" => true, "scope" => "team" }
        }
      )
      agent_profile = tenant.profiles.find_by!(key: "agent")
      owner = create(:admin_user, tenant: tenant, profile: owner_profile)
      manager = create(:admin_user, tenant: tenant, profile: manager_profile, manager: owner)
      peer = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner)
      sign_in manager

      post admin_tasks_path, params: {
        task: {
          title: "Tarefa fora da equipe",
          kind: "follow_up",
          due_at: 1.day.from_now,
          admin_user_id: peer.id
        }
      }

      expect(response).to have_http_status(:redirect)
      expect(Task.last.admin_user_id).to eq(manager.id)
      expect(Task.last.admin_user_id).not_to eq(peer.id)
    end
  end

  describe "PATCH /admin/tasks/:id/complete" do
    it "conclui a tarefa e loga na timeline" do
      lead = create(:lead)
      task = Task.create!(title: "Follow-up", admin_user: admin, lead: lead, status: "pendente")

      patch complete_admin_task_path(task)

      expect(task.reload.status).to eq("concluida")
      expect(task.completed_at).to be_present
      expect(lead.activities.where(kind: "task_completed").count).to eq(1)
    end
  end
end
