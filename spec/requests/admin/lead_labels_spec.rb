require "rails_helper"

RSpec.describe "Admin::LeadLabels", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "labels-#{SecureRandom.hex(8)}@salute.test") }
  let(:lead) { create(:lead, name: "Lead Etiqueta") }

  before do
    host! "localhost"
    sign_in admin
  end

  describe "GET /admin/leads/:lead_id/lead_labels" do
    it "semeia os defaults e devolve o HTML do gerenciador" do
      expect {
        get admin_lead_lead_labels_path(lead)
      }.to change { admin.lead_labels.count }.from(0).to(5)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["manager_html"]).to include("Aplicar ao lead")
      expect(body["manager_html"]).to include("Quente")
      expect(body).to have_key("chips_html")
    end
  end

  describe "POST create" do
    it "cria uma etiqueta do usuário atual" do
      expect {
        post admin_lead_lead_labels_path(lead), params: { lead_label: { name: "Urgente", color: "red" } }
      }.to change { admin.lead_labels.count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(admin.lead_labels.last.name).to eq("Urgente")
    end

    it "rejeita cor inválida" do
      post admin_lead_lead_labels_path(lead), params: { lead_label: { name: "X", color: "rosa" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH update / DELETE destroy" do
    let!(:label) { create(:lead_label, admin_user: admin, name: "Quente", color: "red") }

    it "atualiza nome e cor" do
      patch admin_lead_lead_label_path(lead, label), params: { lead_label: { name: "Muito quente", color: "amber" } }
      expect(response).to have_http_status(:ok)
      expect(label.reload.name).to eq("Muito quente")
      expect(label.color).to eq("amber")
    end

    it "exclui a etiqueta" do
      expect {
        delete admin_lead_lead_label_path(lead, label)
      }.to change { admin.lead_labels.count }.by(-1)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST toggle" do
    let!(:label) { create(:lead_label, admin_user: admin, name: "Quente", color: "red") }

    it "marca e desmarca a etiqueta no lead" do
      expect {
        post toggle_admin_lead_lead_label_path(lead, label)
      }.to change { lead.lead_labelings.count }.by(1)

      body = JSON.parse(response.body)
      expect(body["chips_html"]).to include("Quente")

      expect {
        post toggle_admin_lead_lead_label_path(lead, label)
      }.to change { lead.lead_labelings.count }.by(-1)
    end
  end

  describe "privacidade por usuário" do
    let(:other) { create(:admin_user, :admin) }
    let!(:foreign_label) { create(:lead_label, admin_user: other, name: "Alheia", color: "green") }

    it "não permite operar sobre etiqueta de outro usuário" do
      post toggle_admin_lead_lead_label_path(lead, foreign_label)
      expect(response).to have_http_status(:not_found)
      expect(lead.lead_labelings.count).to eq(0)
    end

    it "não expõe etiquetas de outro usuário no gerenciador" do
      get admin_lead_lead_labels_path(lead)
      body = JSON.parse(response.body)
      expect(body["manager_html"]).not_to include("Alheia")
    end
  end
end
