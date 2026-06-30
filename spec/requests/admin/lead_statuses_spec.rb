require "rails_helper"

RSpec.describe "Admin::LeadStatuses", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "lead-status-admin-#{SecureRandom.hex(6)}@salute.test") }
  let(:other_tenant) { Tenant.create!(name: "Outro status #{SecureRandom.hex(3)}", slug: "outro-status-#{SecureRandom.hex(3)}") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "lista apenas status do tenant atual" do
    admin.tenant.attribute_options.create!(context: "lead", category: "status", name: "Em análise")
    other_tenant.attribute_options.create!(context: "lead", category: "status", name: "Status externo")

    get admin_lead_statuses_path, headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    names = JSON.parse(response.body).map { |row| row.fetch("name") }
    expect(names).to include("Em análise")
    expect(names).not_to include("Status externo")
  end

  it "ignora update de status de outro tenant e cria novos status no tenant atual" do
    external_status = other_tenant.attribute_options.create!(context: "lead", category: "status", name: "Status externo")

    post bulk_update_admin_lead_statuses_path,
         params: {
           statuses: [
             { id: external_status.id, name: "Invadido", description: "Nao deve mudar" },
             { name: "Retorno futuro", description: "Acompanhar depois" }
           ]
         },
         headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(external_status.reload.name).to eq("Status externo")
    expect(admin.tenant.attribute_options.find_by!(context: "lead", category: "status", name: "Retorno futuro")).to be_present
  end
end
