require "rails_helper"

RSpec.describe "Blog", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers
  let(:tenant) { Tenant.default }
  let(:other) { Tenant.create!(name: "Outra conta blog", slug: "outra-conta-blog") }
  let(:category) { tenant.blog_categories.find_or_create_by!(name: "Regiões") }
  let(:owner) { create(:admin_user, :admin, tenant: tenant) }

  def article(account = tenant, **attrs)
    category = account.blog_categories.find_or_create_by!(name: "Regiões")
    account.blog_articles.create!({ title: "Guia de bairros", content: "<h2>A cidade</h2><p>Conteúdo público do artigo.</p>", status: "published", blog_categories: [category] }.merge(attrs))
  end

  before { host! "localhost" }

  it "serves correctly sized JPEG social images for blog, category and article" do
    post = article
    post.cover.attach(io: File.open(Rails.root.join("spec/fixtures/files/watermark.png")), filename: "cover.png", content_type: "image/png", metadata: {tenant_id: tenant.id, purpose: "blog"})
    post.save!
    ["/blog", "/blog/categoria/#{post.blog_categories.first.slug}", "/#{post.slug}"].each do |path|
      get path, headers: { "HTTP_USER_AGENT" => "WhatsApp/2.23.20.0" }
      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css('meta[property="og:image:type"]')["content"]).to eq("image/jpeg")
      expect(page.at_css('meta[property="og:image:width"]')["content"]).to eq("1200")
      expect(page.at_css('meta[property="og:image:height"]')["content"]).to eq("630")
      expect(page.at_css('meta[property="og:image:alt"]')["content"]).to eq(post.title)
      expect(page.at_css('meta[property="og:image"]')["content"]).to include("/representations/proxy/")
    end
    variant = post.cover.variant(:blog_social).processed
    expect(variant.image.blob.content_type).to eq("image/jpeg")
    variant.image.blob.open do |file|
      expect(MiniMagick::Image.open(file.path).dimensions).to eq([1200, 630])
    end
  end

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

  it "generates article metadata from actual content while preserving manual SEO" do
    post = article(meta_title: "Título editorial", meta_description: "Descrição editorial.")
    get "/#{post.slug}"
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("title").text).to eq("Título editorial")
    expect(doc.at_css('meta[name="description"]')["content"]).to eq("Descrição editorial.")
    expect(doc.at_css('meta[name="robots"]')["content"]).to include("max-image-preview:large")
    graph = JSON.parse(doc.at_css('script[type="application/ld+json"]').text).fetch("@graph")
    posting = graph.find { |node| node["@type"] == "BlogPosting" }
    expect(posting).to include("headline" => post.title, "datePublished" => post.published_at.iso8601, "articleSection" => ["Regiões"])
    expect(posting["url"]).to end_with("/#{post.slug}")
    expect(graph.last["@type"]).to eq("BreadcrumbList")
  end

  it "gives paginated archives their own canonical and excludes internal searches from indexing" do
    25.times { |i| article(slug: "pagina-#{i}") }
    get "/blog", params: { page: 3 }
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('link[rel="canonical"]')["href"]).to end_with("/blog?page=3")
    expect(doc.at_css('meta[name="robots"]')["content"]).to start_with("index, follow")
    graph = JSON.parse(doc.at_css('script[type="application/ld+json"]').text).fetch("@graph")
    expect(graph.first["mainEntity"]["itemListElement"].first["position"]).to eq(25)
    get "/blog", params: { q: "Guia" }
    expect(Nokogiri::HTML(response.body).at_css('meta[name="robots"]')["content"]).to eq("noindex, follow")
  end

  it "includes only populated public categories in the sitemap and describes their archive" do
    article
    empty = tenant.blog_categories.create!(name: "Categoria vazia")
    xml = Seo::SitemapBuilder.new(base_url: "https://example.test", url_helpers: Rails.application.routes.url_helpers, tenant: tenant).to_xml
    expect(xml).to include("/blog/categoria/#{category.slug}")
    expect(xml).not_to include("/blog/categoria/#{empty.slug}")
    get "/blog/categoria/#{category.slug}"
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('meta[name="description"]')["content"]).to include(category.name)
    expect(response.body).to include("CollectionPage", "BreadcrumbList")
  end

  it "offers the published link only for currently public articles" do
    visible = article
    draft = article(slug: "oculto", status: "draft")
    future = article(slug: "agendado", published_at: 1.day.from_now)
    sign_in owner
    get "/admin/blog_articles"
    links = Nokogiri::HTML(response.body).css("a").select { |a| a.text.include?("Ver artigo publicado") }
    expect(links.map { |a| a["href"] }).to eq([visible.public_url(fallback_base_url: "http://localhost")])
    [draft, future].each do |post|
      get "/admin/blog_articles/#{post.id}/edit"
      expect(response.body).not_to include("Ver artigo publicado")
    end
  end

  it "allows crawling signed public image proxies while retaining private route exclusions" do
    get "/robots.txt"
    expect(response.body).to include("Disallow: /admin/", "Disallow: /rails/", "Allow: /rails/active_storage/blobs/proxy/", "Allow: /rails/active_storage/representations/proxy/")
  end

  it "publishes at the scheduled instant and removes inactive articles from every public entry point" do
    travel_to Time.zone.local(2026, 9, 9, 10, 0) do
      scheduled = article(status: "scheduled", published_at: 1.hour.from_now)
      get "/#{scheduled.slug}"
      expect(response).to have_http_status(:not_found)
      expect(scheduled.publication_status).to eq("scheduled")
      sign_in owner
      get "/admin/blog_articles", params: { status: "scheduled" }
      expect(response.body).to include(scheduled.title, "Agendado")
      get "/admin/blog_articles", params: { status: "published" }
      expect(response.body).not_to include(scheduled.title)
      sign_out owner
      travel 1.hour
      get "/#{scheduled.slug}"
      expect(response).to have_http_status(:ok)
      expect(scheduled.publication_status).to eq("published")
      expect(tenant.blog_articles.with_publication_status("scheduled")).not_to include(scheduled)
      expect(tenant.blog_articles.with_publication_status("published")).to include(scheduled)
      sign_in owner
      patch "/admin/blog_articles/#{scheduled.id}", params: { blog_article: { status: "inactive", blog_category_ids: scheduled.blog_category_ids } }
      expect(response).to have_http_status(:see_other)
      sign_out owner
      get "/#{scheduled.slug}"
      expect(response).to have_http_status(:not_found)
      get "/blog"
      expect(response.body).not_to include(scheduled.title)
      xml = Seo::SitemapBuilder.new(base_url: "https://example.test", url_helpers: Rails.application.routes.url_helpers, tenant: tenant).to_xml
      expect(xml).not_to include("/#{scheduled.slug}")
    end
  end

  it "configures a blog home section and displays only the latest public articles of its tenant" do
    sign_in owner
    post "/admin/home_sections", params: { home_section: { title: "Novidades do blog", content_kind: "blog", active: "1", property_filters: { locacao: "1" } } }
    expect(response).to redirect_to("/admin/home_sections")
    section = tenant.home_sections.find_by!(title: "Novidades do blog")
    expect(section).to be_blog
    expect(section.property_filters).to eq({})
    get "/admin/home_sections/#{section.id}/edit"
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css('select[name="home_section[content_kind]"] option[selected]')["value"]).to eq("blog")
    get "/admin/home_sections/#{section.id}"
    expect(response).to have_http_status(:ok)
    other.home_sections.create!(title: "Outra home", section_type: :blog, active: true)
    get "/admin/home_sections/#{other.home_sections.last.id}/edit"
    expect(response).to have_http_status(:not_found)
    posts = 4.times.map { |i| article(title: "Notícia home #{i}", published_at: (i + 1).days.ago) }
    article(title: "Rascunho home", status: "draft")
    article(title: "Inativo home", status: "inactive")
    article(title: "Futuro home", status: "scheduled", published_at: 1.day.from_now)
    article(other, title: "Outra conta home")
    sign_out owner
    get "/"
    expect(response).to have_http_status(:ok)
    block = Nokogiri::HTML(response.body).at_css('[data-public-home-section-type="blog"]')
    expect(block.text).to include(section.title, "Ver todos os artigos", *posts.first(3).map(&:title))
    expect(block.text).not_to include(posts.last.title, "Rascunho home", "Inativo home", "Futuro home", "Outra conta home")
    expect(response.headers["Cache-Control"]).to include("no-cache")
    section.update!(active: false)
    get "/"
    expect(Nokogiri::HTML(response.body).at_css('[data-public-home-section-type="blog"]')).to be_nil
  end

  it "omits empty blog sections on the home" do
    tenant.home_sections.create!(title: "Blog vazio", section_type: :blog, active: true)
    get "/"
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css('[data-public-home-section-type="blog"]')).to be_nil
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
