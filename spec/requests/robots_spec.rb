require "rails_helper"

RSpec.describe "Robots", type: :request do
  it "monta sitemap com o host público da requisição" do
    host! "localhost"

    get "/robots.txt"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/plain")
    expect(response.body).to include("Sitemap: http://localhost/sitemap.xml")
    expect(response.body).not_to include("saluteimoveis")
  end
end
