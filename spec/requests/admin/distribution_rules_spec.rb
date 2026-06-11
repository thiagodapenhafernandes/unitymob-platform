require "rails_helper"

RSpec.describe "Admin::DistributionRules", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "salva a fila de distribuicao a partir do select de corretores ao criar" do
    receiver = create(:admin_user, :admin, name: "Administrador")

    post admin_distribution_rules_path, params: {
      agent_select: [receiver.id.to_s],
      distribution_rule: {
        name: "Regra Meta",
        business_type: "ambos",
        distribution_mode: "rotary",
        active: "1",
        source_site: "1",
        source_meta: "0",
        source_portal: "0",
        source_webhook: "0"
      }
    }

    expect(response).to redirect_to(admin_distribution_rule_path(DistributionRule.last))
    rule = DistributionRule.last
    expect(rule.distribution_rule_agents.pluck(:admin_user_id)).to eq([receiver.id])
  end

  it "atualiza a fila de distribuicao a partir do select de corretores ao editar" do
    first_receiver = create(:admin_user, :admin)
    second_receiver = create(:admin_user, :admin)
    rule = create(:distribution_rule)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: first_receiver)

    patch admin_distribution_rule_path(rule), params: {
      agent_select: [second_receiver.id.to_s],
      distribution_rule: {
        name: rule.name,
        business_type: "ambos",
        distribution_mode: "rotary",
        active: "1",
        source_site: "1",
        source_meta: "0",
        source_portal: "0",
        source_webhook: "0"
      }
    }

    expect(response).to redirect_to(admin_distribution_rule_path(rule))
    expect(rule.reload.distribution_rule_agents.pluck(:admin_user_id)).to eq([second_receiver.id])
  end

  it "preserva a ordem enviada pela fila quando os nested attributes estao presentes" do
    first_receiver = create(:admin_user, :admin)
    second_receiver = create(:admin_user, :admin)
    rule = create(:distribution_rule)
    first_agent = create(:distribution_rule_agent, distribution_rule: rule, admin_user: first_receiver, position: 1)
    second_agent = create(:distribution_rule_agent, distribution_rule: rule, admin_user: second_receiver, position: 2)

    patch admin_distribution_rule_path(rule), params: {
      agent_select: [first_receiver.id.to_s, second_receiver.id.to_s],
      distribution_rule: {
        name: rule.name,
        business_type: "ambos",
        distribution_mode: "rotary",
        active: "1",
        source_site: "1",
        source_meta: "0",
        source_portal: "0",
        source_webhook: "0",
        distribution_rule_agents_attributes: {
          "0" => { id: first_agent.id, admin_user_id: first_receiver.id, position: 2, weight: 1 },
          "1" => { id: second_agent.id, admin_user_id: second_receiver.id, position: 1, weight: 1 }
        }
      }
    }

    expect(response).to redirect_to(admin_distribution_rule_path(rule))
    expect(rule.reload.distribution_rule_agents.order(:position).pluck(:admin_user_id)).to eq([second_receiver.id, first_receiver.id])
  end

  it "permite reordenar a fila pela tela de detalhe" do
    first_receiver = create(:admin_user, :admin)
    second_receiver = create(:admin_user, :admin)
    rule = create(:distribution_rule)
    first_agent = create(:distribution_rule_agent, distribution_rule: rule, admin_user: first_receiver, position: 1)
    second_agent = create(:distribution_rule_agent, distribution_rule: rule, admin_user: second_receiver, position: 2)

    patch reorder_agents_admin_distribution_rule_path(rule), params: {
      agent_ids: [second_agent.id, first_agent.id]
    }

    expect(response).to redirect_to(admin_distribution_rule_path(rule))
    expect(rule.reload.distribution_rule_agents.order(:position).pluck(:id)).to eq([second_agent.id, first_agent.id])
  end

  it "mostra as configuracoes principais da regra no detalhe" do
    meta_page = create(:meta_facebook_page, name: "Salute Imóveis", page_id: "page-1")
    meta_form = create(:meta_lead_form, meta_facebook_page: meta_page, name: "Captação Praia Brava", form_id: "form-1")
    rule = create(
      :distribution_rule,
      name: "Elite",
      source_meta: true,
      source_webhook: true,
      source_site: true,
      notify_email: true,
      meta_page_ids: [meta_page.page_id],
      meta_forms: [meta_form.form_id],
      webhook_tags: ["elite"]
    )

    get admin_distribution_rule_path(rule)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Configuração da regra")
    expect(response.body).to include("Salute Imóveis")
    expect(response.body).to include("Captação Praia Brava")
    expect(response.body).to include("Check-in geolocalizado")
    expect(response.body).to include("Notificações")
  end
end
