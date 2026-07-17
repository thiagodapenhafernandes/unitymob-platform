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
end
