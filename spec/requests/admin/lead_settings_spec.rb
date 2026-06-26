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
end
