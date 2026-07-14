require "rails_helper"

RSpec.describe "Admin::LeadSettings", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "exibe a escolha operacional do destino do push" do
    get edit_admin_lead_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ao tocar na notificação")
    expect(response.body).to include("Detalhes do lead primeiro")
    expect(response.body).to include("WhatsApp do lead direto")
    document = Nokogiri::HTML(response.body)
    expect(document.css("fieldset.ax-radio-group").size).to eq(4)
    expect(document.at_css('fieldset.ax-radio-group input[name="lead_setting[push_lead_click_action]"]')).to be_present
    expect(document.at_css('dl.ax-status-list[aria-label="Resumo das configurações de leads"]')).to be_present
    expect(document.at_css(".ax-form-actions--static")).to be_present
  end

  it "salva o destino operacional do clique no push pela tela de leads" do
    LeadSetting.instance
    PushSetting.instance.update!(lead_click_action: "whatsapp")

    patch admin_lead_setting_path, params: {
      lead_setting: {
        stickiness_enabled: "0",
        stickiness_match: "phone",
        stickiness_owner: "attended",
        stickiness_fallback: "active_in_rule",
        stickiness_window_days: "",
        secure_links_enabled: "1",
        secure_link_expiry_days: "7",
        secure_link_whatsapp: "1",
        secure_link_email: "1",
        secure_link_push: "1",
        push_lead_click_action: "system",
        notify_on_distribution: "1",
        notify_on_sticky: "1",
        notify_on_redistribution: "1",
        notify_on_shark_tank: "1",
        notify_on_direct_assignment: "1",
        notify_on_reassignment: "1",
        notify_on_lost_turn: "0"
      }
    }

    expect(response).to redirect_to(edit_admin_lead_setting_path)
    expect(PushSetting.instance.reload.lead_click_action_value).to eq("system")
  end

  it "salva apenas a configuracao de leads do tenant autenticado" do
    other_tenant = Tenant.create!(name: "Conta leads externa #{SecureRandom.hex(3)}", slug: "leads-externa-#{SecureRandom.hex(4)}")
    other_setting = LeadSetting.create!(tenant: other_tenant, stickiness_enabled: true)

    patch admin_lead_setting_path, params: {
      lead_setting: {
        stickiness_enabled: "0",
        stickiness_match: "phone",
        stickiness_owner: "attended",
        stickiness_fallback: "active_in_rule",
        stickiness_window_days: "",
        secure_links_enabled: "0",
        secure_link_expiry_days: "7",
        push_lead_click_action: "system"
      }
    }

    expect(response).to redirect_to(edit_admin_lead_setting_path)
    expect(other_setting.reload).to be_stickiness_enabled
    expect(LeadSetting.instance(tenant: admin.tenant)).not_to be_stickiness_enabled
  end

  it "bloqueia acesso direto sem permissao de gerenciar distribuicao" do
    profile = Profile.create!(
      tenant: admin.tenant,
      name: "Sem distribuição #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 7_500,
      permissions: {}
    )
    viewer = create(:admin_user, tenant: admin.tenant, profile: profile, role: :editor)
    sign_out admin
    sign_in viewer

    get edit_admin_lead_setting_path

    expect(response).to redirect_to(admin_root_path)
  end
end
