require "rails_helper"
RSpec.describe BlogArticle do
  include ActiveSupport::Testing::TimeHelpers
  let(:tenant) { Tenant.default }
  it "reserves application routes and landing page slugs in both directions" do
    landing = tenant.landing_pages.create!(title: "Busca especial", slug: "busca-especial")
    %w[admin blog imoveis up jobs].push(landing.slug).each do |slug|
      post = tenant.blog_articles.new(title: "Teste", slug: slug)
      expect(post).not_to be_valid
      expect(post.errors[:slug]).to be_present
    end
    tenant.blog_articles.create!(title: "Minha notícia", slug: "minha-noticia")
    page = tenant.landing_pages.new(title: "Minha notícia", slug: "minha-noticia")
    expect(page).not_to be_valid
    expect(page.errors[:slug]).to be_present
  end
  it "requires a category when publishing and rejects external images" do
    article = tenant.blog_articles.new(title: "Notícia", status: "published", content: '<p>Texto</p><img src="https://outside.example/file.png">')
    expect(article).not_to be_valid
    expect(article.errors[:blog_categories]).to be_present
    expect(article.errors[:content]).to be_present
  end
  it "rejects references to non-blog attachments even within the same tenant" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("private"), filename: "private.pdf", content_type: "application/pdf", service_name: "test", metadata: { tenant_id: tenant.id })
    article = tenant.blog_articles.new(title: "Documento", content: ActionText::Attachment.from_attachable(blob).to_html)
    expect(article).not_to be_valid
    expect(article.errors[:content]).to be_present
  end
  it "requires future dates and complete content for scheduling, and allows cancelling schedules" do
    travel_to Time.zone.local(2026, 9, 9, 10, 0) do
      post = tenant.blog_articles.new(title: "Agendado", status: "scheduled")
      expect(post).not_to be_valid
      expect(post.errors[:published_at]).to be_present
      expect(post.errors[:content]).to be_present
      expect(post.errors[:blog_categories]).to be_present
      post.content = "Conteúdo"
      post.blog_categories = [tenant.blog_categories.create!(name: "Agenda")]
      post.published_at = 1.minute.ago
      expect(post).not_to be_valid
      post.published_at = 1.hour.from_now
      post.save!
      post.update!(published_at: 2.hours.from_now)
      travel 1.hour
      expect(post).not_to be_publicly_visible
      post.update!(status: "draft")
      travel 2.hours
      expect(post).not_to be_publicly_visible
      post.update!(status: "published")
      expect(post).to be_publicly_visible
    end
  end

end
