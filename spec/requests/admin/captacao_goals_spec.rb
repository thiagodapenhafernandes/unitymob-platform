require "rails_helper"

RSpec.describe "Admin::CaptacaoGoals", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "captacao-goals-#{SecureRandom.hex(6)}@salute.test") }
  let(:other_tenant) { Tenant.create!(name: "Outra operação #{SecureRandom.hex(3)}", slug: "outra-operacao-#{SecureRandom.hex(3)}") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "lista apenas metas do tenant atual" do
    current_region = "Região atual #{SecureRandom.hex(4)}"
    other_region = "Região externa #{SecureRandom.hex(4)}"
    current_goal = create(:captacao_goal, tenant: admin.tenant, kind: :venda, start_date: Date.new(2098, 1, 1), end_date: Date.new(2098, 1, 31), foco_regiao: current_region)
    create(:captacao_goal, tenant: other_tenant, kind: :venda, start_date: Date.new(2098, 1, 1), end_date: Date.new(2098, 1, 31), foco_regiao: other_region)

    get admin_captacao_goals_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(current_goal.period_label, current_region)
    expect(response.body).not_to include(other_region)
  end

  it "renderiza o formulario com todos os campos persistidos" do
    get new_admin_captacao_goal_path

    expect(response).to have_http_status(:ok)
    %w[start_date end_date kind target foco_regiao foco_valor_min foco_valor_max].each do |field|
      expect(response.body).to include("captacao_goal_#{field}")
    end
  end
end
