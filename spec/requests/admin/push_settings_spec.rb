require "rails_helper"

RSpec.describe "Admin::PushSettings", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  let(:profile_owner) { Tenant.default.profiles.find_by!(key: "tenant_owner") }

  it "bloqueia o dono de conta de VER a tela (push/VAPID é exclusivo do Admin do Sistema)" do
    owner = create(:admin_user, profile: profile_owner, super_admin: false)
    sign_in owner, scope: :admin_user

    get edit_admin_push_setting_path

    expect(response).to redirect_to(admin_root_path)
    expect(flash[:alert]).to match(/Admin do Sistema/i)
  end

  it "bloqueia o dono de conta de ALTERAR o VAPID global" do
    owner = create(:admin_user, profile: profile_owner, super_admin: false)
    sign_in owner, scope: :admin_user

    PushSetting.instance.update!(enabled: false)

    patch admin_push_setting_path, params: { push_setting: { enabled: "1" } }

    expect(response).to redirect_to(admin_root_path)
    expect(PushSetting.instance.reload.enabled?).to be(false)
  end

  it "permite ao Admin do Sistema salvar o VAPID global" do
    sys = create(:admin_user, super_admin: true)
    sign_in sys, scope: :admin_user

    PushSetting.instance.update!(enabled: false)

    patch admin_push_setting_path, params: { push_setting: { enabled: "1" } }

    expect(response).to redirect_to(edit_admin_push_setting_path)
    expect(PushSetting.instance.reload.enabled?).to be(true)
  end
end
