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
