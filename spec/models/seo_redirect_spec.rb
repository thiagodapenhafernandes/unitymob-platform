require "rails_helper"

RSpec.describe SeoRedirect do
  it "permite destino interno ou domínio ativo da conta" do
    tenant = Tenant.create!(name: "Conta SEO #{SecureRandom.hex(3)}", slug: "conta-seo-#{SecureRandom.hex(3)}")
    tenant.tenant_domains.create!(hostname: "salute.example.com", active: true, primary_domain: true)
    redirect = tenant.seo_redirects.new(from_path: "/antigo", to_path: "/novo", status_code: 301)

    expect(redirect).to be_valid

    redirect.to_path = "https://www.salute.example.com/novo"
    expect(redirect).to be_valid

    redirect.to_path = "https://evil.example/phishing"
    expect(redirect).not_to be_valid
    expect(redirect.errors[:to_path]).to be_present
  end
end
