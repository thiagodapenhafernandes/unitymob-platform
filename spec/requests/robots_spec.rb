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

  it "usa o domínio público configurado no sitemap anunciado" do
    Tenant.default.tenant_domains.create!(hostname: "conexaobc.com", primary_domain: true)
    host! "localhost"

    get "/robots.txt"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sitemap: https://conexaobc.com/sitemap.xml")
    expect(response.body).not_to include("http://localhost/sitemap.xml")
  end
end
