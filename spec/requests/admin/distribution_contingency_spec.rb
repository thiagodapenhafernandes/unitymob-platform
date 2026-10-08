require "rails_helper"

RSpec.describe "Admin configuração de contingência", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }
  let(:target) { create(:distribution_rule, tenant: tenant, name: "Central receptora") }
  let(:source) { create(:distribution_rule, tenant: tenant) }
  before do
    host! "localhost"
    sign_in admin
  end

  it "mostra controles compartilhados e somente destinos da conta" do
    target
    outsider = create(:distribution_rule, tenant: Tenant.create!(name: "Outra", slug: "other-config-#{SecureRandom.hex(4)}"), name: "Outro cliente")
    get edit_admin_distribution_rule_path(source)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("input[name='distribution_rule[contingency_enabled]'].ax-switch__input")).to be_present
    expect(doc.css("input[name='distribution_rule[contingency_triggers][]'][type='checkbox']").size).to eq(5)
    select = doc.at_css("select[name='distribution_rule[contingency_rule_id]']")
    expect(select.text).to include(target.name)
    expect(select.text).not_to include(outsider.name)
    expect(select.css("option").map { |o| o['value'] }).not_to include(source.id.to_s)
    if ENV["CONTINGENCY_PREVIEW"]
      File.write(ENV.fetch("CONTINGENCY_PREVIEW"), response.body)
    end
  end

  it "salva gatilhos, destino e prazos pela tela da regra" do
    patch admin_distribution_rule_path(source), params: { distribution_rule: {
      contingency_enabled: "1", contingency_rule_id: target.id, contingency_triggers: ["", "unavailable", "pool_timeout"],
      contingency_unavailable_minutes: "0", contingency_pool_minutes: "15", contingency_acceptance_minutes: "60"
    } }
    expect(response).to redirect_to(admin_distribution_rule_path(source))
    expect(source.reload).to have_attributes(contingency_enabled: true, contingency_rule_id: target.id,
      contingency_triggers: %w[unavailable pool_timeout], contingency_pool_minutes: 15)
  end

  it "rejeita destino de outra conta recebido por requisição direta" do
    outsider = create(:distribution_rule, tenant: Tenant.create!(name: "Outra", slug: "other-request-#{SecureRandom.hex(4)}"))
    patch admin_distribution_rule_path(source), params: { distribution_rule: {
      contingency_enabled: "1", contingency_rule_id: outsider.id, contingency_triggers: ["unavailable"]
    } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(source.reload.contingency_enabled?).to eq(false)
  end

  it "salva o destino padrão da conta e permite desativá-lo" do
    patch admin_lead_setting_path, params: { lead_setting: { default_distribution_rule_id: target.id } }
    expect(response).to redirect_to(edit_admin_lead_setting_path)
    expect(LeadSetting.instance(tenant: tenant).default_distribution_rule_id).to eq(target.id)
    patch admin_lead_setting_path, params: { lead_setting: { default_distribution_rule_id: "" } }
    expect(LeadSetting.instance(tenant: tenant).default_distribution_rule_id).to be_nil
  end

  it "mostra o destino final sem permitir ativar outro encaminhamento pela interface" do
    source.update!(contingency_enabled: true, contingency_rule: target, contingency_triggers: ["unavailable"])
    get edit_admin_distribution_rule_path(target)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("input[name='distribution_rule[contingency_enabled]'][type='checkbox']")['disabled']).to be_present
    expect(response.body).to include("Esta regra é um destino final")
  end

  it "não aceita destino padrão de outra conta" do
    outsider = create(:distribution_rule, tenant: Tenant.create!(name: "Outra", slug: "other-default-#{SecureRandom.hex(4)}"))
    patch admin_lead_setting_path, params: { lead_setting: { default_distribution_rule_id: outsider.id } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(LeadSetting.instance(tenant: tenant).reload.default_distribution_rule_id).to be_nil
  end

  it "exige permissão para configurar encaminhamento" do
    rule = source
    sign_out admin
    sign_in create(:admin_user, tenant: tenant)
    patch admin_distribution_rule_path(rule), params: { distribution_rule: { contingency_enabled: true } }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(rule.reload.contingency_enabled?).to eq(false)
  end
end
