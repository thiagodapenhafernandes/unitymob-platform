require "rails_helper"

RSpec.describe "Admin leads kanban column", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "kanbancol-#{SecureRandom.hex(8)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "paginates the column without a total count query" do
    7.times { |i| create(:lead, tenant: admin.tenant, name: "Col Lead #{i}", status: "Novo", origin: "site") }

    get kanban_column_admin_leads_path(view: "kanban", status: "Novo")
    expect(response).to have_http_status(:ok)
    first = JSON.parse(response.body)
    expect(first["loaded_count"]).to eq(5)
    expect(first["has_more"]).to eq(true)
    expect(first["next_offset"]).to eq(5)
    expect(first).not_to have_key("total")

    get kanban_column_admin_leads_path(view: "kanban", status: "Novo", offset: 5)
    expect(response).to have_http_status(:ok)
    second = JSON.parse(response.body)
    expect(second["loaded_count"]).to eq(2)
    expect(second["has_more"]).to eq(false)
    expect(second["next_offset"]).to eq(7)
    expect(second["html"]).to include("Col Lead", "Origem:", "Sem corretor atribuído", "Contato geral")
    expect(second["html"]).not_to include("Conversão:")
    expect(second["html"]).to include("ax-board__card-section--property", "data-lead-kanban-status-badge", "Ver detalhes")
  end
end
