require "rails_helper"

RSpec.describe "Admin sessions", type: :request do
  it "renders the sign-in page without requiring an authenticated tenant context" do
    host! "localhost"

    get new_admin_user_session_path

    expect(response).to have_http_status(:ok)
  end

  it "issues a persistent remember cookie on custom sign-in" do
    host! "localhost"
    admin = create(:admin_user, :admin, email: "remember-login-#{SecureRandom.hex(8)}@salute.test")
    get new_admin_user_session_path
    authenticity_token = response.body[/name="authenticity_token" value="([^"]+)"/, 1]

    post admin_user_session_path, params: {
      authenticity_token: authenticity_token,
      admin_user: { email: admin.email, password: "password123" }
    }

    remember_cookie = response.headers["Set-Cookie"].to_s

    expect(response).to redirect_to(admin_root_path)
    expect(remember_cookie).to include("remember_admin_user_token=")
    expect(admin.reload.remember_created_at).to be_present
  end

  it "redirects a normal browser logout to the web sign-in page" do
    host! "localhost"
    admin = create(:admin_user, :admin)
    sign_in_as(admin)

    delete destroy_admin_user_session_path

    expect(response).to redirect_to(new_admin_user_session_path)
  end

  it "redirects a native app logout to the app's local bootstrap screen" do
    host! "localhost"
    admin = create(:admin_user, :admin)
    sign_in_as(admin)

    delete destroy_admin_user_session_path, headers: { "HTTP_USER_AGENT" => "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0) UnitymobFieldApp" }

    expect(response).to redirect_to("capacitor://localhost/index.html?logged_out=1")
  end

  it "redirects a native Android app logout to the https localhost bootstrap screen" do
    host! "localhost"
    admin = create(:admin_user, :admin)
    sign_in_as(admin)

    delete destroy_admin_user_session_path, headers: { "HTTP_USER_AGENT" => "Mozilla/5.0 (Linux; Android 14) UnitymobFieldApp" }

    expect(response).to redirect_to("https://localhost/index.html?logged_out=1")
  end

  private

  # Este projeto não usa o helper padrão Devise::Test::IntegrationHelpers em
  # specs de request — login é sempre via POST real (mesmo padrão de
  # spec/requests/field/check_ins_spec.rb).
  def sign_in_as(admin)
    get new_admin_user_session_path
    authenticity_token = response.body[/name="authenticity_token" value="([^"]+)"/, 1]

    post admin_user_session_path, params: {
      authenticity_token: authenticity_token,
      admin_user: { email: admin.email, password: "password123" }
    }
  end
end
