require "rails_helper"

RSpec.describe "Account llms.txt", type: :request do
  let(:tenant) { Tenant.default }

  def article(account, **attributes)
    category = account.blog_categories.find_or_create_by!(name: "Regiões")
    account.blog_articles.create!({ blog_categories: [category], title: "Guia público", content: "<p>Conteúdo</p>", status: "published" }.merge(attributes))
  end

  it "generates public Markdown with the account identity and canonical domain" do
    LayoutSetting.instance(tenant: tenant).update!(site_name: "Imóveis & Companhia")
    FooterSetting.instance(tenant: tenant).update!(about_text: "<p>Equipe imobiliária local.</p>", email: "publico@example.com")
    profile = PublicSiteProfile.current(tenant: tenant)
    profile.creci = "1234-J"
    expect(profile.save).to eq(true)
    tenant.tenant_domains.create!(hostname: "conexaobc.com", primary_domain: true)
    host! "localhost"
    get "/llms.txt"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/plain")
    expect(response.body).to include("# Imóveis & Companhia", "> Equipe imobiliária local.", "CRECI: 1234-J", "publico@example.com", "https://conexaobc.com/imoveis", "https://conexaobc.com/sitemap.xml")
    expect(response.body).not_to include("<html", "<p>", "localhost", "40.000", "Salute Imóveis")
  end

  it "isolates accounts by domain and excludes unpublished and foreign articles" do
    other = Tenant.create!(name: "Outra imobiliária", slug: "outra-llms")
    other.tenant_domains.create!(hostname: "unitymob.com.br", primary_domain: true, active: true)
    FooterSetting.instance(tenant: other).update!(about_text: "Descrição exclusiva", email: "outra@example.com")
    article(tenant, title: "Artigo de outra conta")
    article(other, title: "Rascunho privado", status: "draft")
    article(other, title: "Artigo futuro", published_at: 1.day.from_now)
    6.times { |index| article(other, title: "Artigo público #{index}", published_at: index.hours.ago) }
    host! "unitymob.com.br"
    get "/llms.txt", params: { tenant: tenant.slug }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("# Outra imobiliária", "Descrição exclusiva", "outra@example.com", "Artigo público 0", "Artigo público 4")
    expect(response.body).not_to include("Artigo de outra conta", "Rascunho privado", "Artigo futuro", "Artigo público 5")
  end

  it "refreshes cached public data after an account change" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    host! "localhost"
    FooterSetting.instance(tenant: tenant).update!(about_text: "Descrição inicial")
    get "/llms.txt"
    expect(response.body).to include("Descrição inicial")
    FooterSetting.instance(tenant: tenant).update!(about_text: "Descrição atualizada")
    PublicSite::PageVersion.bump(tenant.id)
    get "/llms.txt"
    expect(response.body).to include("Descrição atualizada")
    expect(response.body).not_to include("Descrição inicial")
  ensure
    Rails.cache = original_cache
  end
end
