require "rails_helper"

RSpec.describe "Blog", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:tenant) { Tenant.default }
  let(:other) { Tenant.create!(name: "Outra conta blog", slug: "outra-conta-blog") }
  let(:category) { tenant.blog_categories.find_or_create_by!(name: "Regiões") }
  let(:owner) { create(:admin_user, :admin, tenant: tenant) }

  def article(account = tenant, **attrs)
    category = account.blog_categories.find_or_create_by!(name: "Regiões")
    account.blog_articles.create!({ title: "Guia de bairros", content: "<h2>A cidade</h2><p>Conteúdo público do artigo.</p>", status: "published", blog_categories: [category] }.merge(attrs))
  end

  before { host! "localhost" }

  it "serves the article at the root with category, canonical metadata, no home SEO and a table of contents" do
    post = article
    get "/#{post.slug}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(post.title, "#secao-1", "BlogPosting", "/#{post.slug}")
    expect(response.body).to include("Conteúdo público do artigo.")
  end

  it "only lists published articles of this tenant in the sitemap" do
    visible = article
    draft = article(slug: "rascunho-sitemap", status: "draft")
    foreign = article(other, slug: "outra-conta-sitemap")
    xml = Seo::SitemapBuilder.new(base_url: "https://example.test", url_helpers: Rails.application.routes.url_helpers, tenant: tenant).to_xml
    expect(xml).to include("https://example.test/#{visible.slug}", "https://example.test/blog")
    expect(xml).not_to include(draft.slug, foreign.slug)
  end

  it "does not publish drafts or future articles" do
    draft = article(status: "draft", slug: "rascunho")
    future = article(published_at: 1.day.from_now, slug: "futuro")
    [draft, future].each do |post|
      get "/#{post.slug}"
      expect(response).to have_http_status(:not_found)
    end
    get "/blog"
    expect(response.body).not_to include("Guia de bairros")
  end

  it "resolves the tenant by domain even with another tenant's query parameter" do
    first = article(title: "Artigo da primeira conta")
    second = article(other, title: "Artigo exclusivo da segunda conta")
    TenantDomain.create!(tenant: other, hostname: "unitymob.com.br", active: true)
    host! "unitymob.com.br"
    get "/#{first.slug}", params: { tenant: tenant.slug }
    expect(response).to have_http_status(:not_found)
    get "/#{second.slug}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(second.title)
    expect(response.body).not_to include(first.title)
    get "/blog"
    expect(response.body).to include(second.title)
    expect(response.body).not_to include(first.title)
  end

  it "creates, edits and previews articles within the current account" do
    sign_in owner
    post "/admin/blog_articles", params: { blog_article: { title: "Novo conteúdo", content: "<p>Texto</p>", status: "published", blog_category_ids: [category.id] } }
    expect(response).to have_http_status(:see_other)
    created = tenant.blog_articles.find_by!(title: "Novo conteúdo")
    get "/admin/blog_articles/#{created.id}/edit"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("trix-editor", "Criar categoria")
    get "/admin/blog_articles/#{created.id}/preview"
    expect(response).to have_http_status(:ok)
    expect(response.headers["X-Robots-Tag"]).to include("noindex")
  end

  it "does not access another account's article or use its categories" do
    foreign = article(other)
    sign_in owner
    get "/admin/blog_articles/#{foreign.id}/edit"
    expect(response).to have_http_status(:not_found)
    sign_in owner
    delete "/admin/blog_articles/#{foreign.id}"
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload).to be_persisted
    sign_in owner
    post "/admin/blog_articles", params: { blog_article: { title: "Inválido", blog_category_ids: foreign.blog_category_ids } }
    expect(response).to have_http_status(:not_found)
  end

  it "rolls category changes back when an article fails validation" do
    existing = article
    another = tenant.blog_categories.create!(name: "Outra categoria")
    sign_in owner
    patch "/admin/blog_articles/#{existing.id}", params: { blog_article: { title: "", blog_category_ids: [another.id] } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(existing.reload.blog_category_ids).to eq([category.id])
  end

  it "filters listings and creates inline categories only in the account" do
    listed = article
    sign_in owner
    get "/admin/blog_articles"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-table__media-record", listed.title, listed.published_at.strftime("%d/%m/%Y"))
    get "/admin/blog_articles", params: { q: "inexistente" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Nenhum artigo encontrado")
    post "/admin/blog_categories", params: { blog_category: { name: "Investimentos", tenant_id: other.id } }, as: :json
    expect(response).to have_http_status(:created)
    expect(tenant.blog_categories.find_by(name: "Investimentos")).to be_present
    expect(other.blog_categories.find_by(name: "Investimentos")).to be_nil
  end

  it "requires marketing permission, including uploads" do
    sign_in create(:admin_user, tenant: tenant)
    get "/admin/blog_articles"
    expect(response).to redirect_to(admin_root_path)
    post "/admin/blog_uploads", as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "uploads with blog ownership and rejects cross-account and non-blog blobs" do
    sign_in owner
    file = fixture_file_upload("spec/fixtures/files/watermark.png", "image/png")
    post "/admin/blog_uploads", params: { file: file }, headers: { "ACCEPT" => "application/json" }
    expect(response).to have_http_status(:created)
    blob = ActiveStorage::Blob.find_signed!(response.parsed_body.fetch("signed_id"))
    expect(blob.metadata).to include("tenant_id" => tenant.id, "purpose" => "blog")
    expect(blob.service_name).to eq("test")
    bad = article(other, status: "draft")
    bad.content = ActionText::Attachment.from_attachable(blob).to_html
    expect(bad).not_to be_valid
    expect(bad.errors[:content]).to be_present
  end
end
