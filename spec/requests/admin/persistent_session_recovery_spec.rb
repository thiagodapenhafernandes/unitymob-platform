require "rails_helper"

RSpec.describe "Persistent native session recovery", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:headers) { { "HTTP_USER_AGENT" => "Mozilla/5.0 (iPhone) UnitymobFieldApp" } }

  def login_and_backup_cookie(admin)
    post "/mobile/sign_in", params: { admin_user: { email: admin.email, password: "password123" } }, headers: headers
    expect(response).to redirect_to(field_root_path)
    cookies["remember_admin_user_token"].tap { |value| expect(value).to be_present }
  end

  def recover_with(cookie)
    cookies.delete("_unitymob_crm_session")
    cookies["remember_admin_user_token"] = cookie
    get field_root_path, headers: headers
  end

  before { host! "localhost" }

  it "rejects a cookie backup after explicit logout" do
    admin = create(:admin_user, :admin)
    backup = login_and_backup_cookie(admin)
    delete destroy_admin_user_session_path, headers: headers

    recover_with(backup)
    expect(response).to redirect_to(new_admin_user_session_path)
  end

  it "rejects a cookie backup after access is revoked" do
    admin = create(:admin_user, :admin)
    backup = login_and_backup_cookie(admin)
    admin.revoke_all_access!

    recover_with(backup)
    expect(response).to redirect_to(new_admin_user_session_path)
  end

  it "applies each account's remember limit to a recovered cookie" do
    admin = create(:admin_user, :admin)
    admin.tenant.update!(session_remember_days: 1)
    backup = login_and_backup_cookie(admin)

    travel_to 2.days.from_now do
      recover_with(backup)
      expect(response).to redirect_to(new_admin_user_session_path)
    end
  end
end
