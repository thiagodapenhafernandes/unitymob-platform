require "rails_helper"

RSpec.describe "Admin login password reveal", type: :request do
  before { host! "localhost" }

  it "renderiza o botão próprio de mostrar senha no login" do
    get "/admin/sign_in"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("login-control--password")
    expect(response.body).to include("data-login-reveal")
    expect(response.body).to include('aria-label="Mostrar senha"')
  end
end
