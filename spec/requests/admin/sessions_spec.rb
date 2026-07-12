require "rails_helper"

RSpec.describe "Admin sessions", type: :request do
  it "renders the sign-in page without requiring an authenticated tenant context" do
    host! "localhost"

    get new_admin_user_session_path

    expect(response).to have_http_status(:ok)
  end
end
