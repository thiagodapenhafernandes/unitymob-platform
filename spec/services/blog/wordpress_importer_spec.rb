require "rails_helper"
require "tmpdir"
RSpec.describe Blog::WordpressImporter do
  it "imports local images into owned storage, preserves content, and is idempotent" do
    Dir.mktmpdir do |dir|
      image = Rails.root.join("spec/fixtures/files/watermark.png")
      FileUtils.cp(image, File.join(dir, "photo.png"))
      source = "https://wordpress.example/photo.png"
      backup = { images: [{ source_url: source, local_file: "photo.png" }], articles: [{ id: 100, slug: "guia-importado", title: "Guia importado", status: "publish", link: "https://wordpress.example/guia-importado/", date_gmt: "2026-01-01T12:00:00", excerpt: "<p>Resumo</p>", content: "<h2>Região</h2><p>Original</p><img src='#{source}' alt='Vista'><script>alert(1)</script>", categories: [{ name: "Praias", slug: "praias" }], images: [{ kind: "featured", source_url: source }] }] }
      path = File.join(dir, "artigos.json")
      File.write(path, backup.to_json)
      importer = described_class.new(tenant: Tenant.default, path: path)
      expect { importer.call }.not_to change(BlogArticle, :count)
      expect(importer.call(execute: true)[:imported]).to eq(1)
      article = Tenant.default.blog_articles.find_by!(wordpress_id: 100)
      expect(article.content.to_plain_text).to include("Original")
      expect(article.content.body.to_html).not_to include("<script", source)
      expect(article.cover.blob.service_name).to eq("test")
      expect(article.content.body.attachables.first).to eq(article.cover.blob)
      expect { importer.call(execute: true) }.not_to change(ActiveStorage::Blob, :count)
      expect(article.blog_categories.first.tenant_id).to eq(Tenant.default.id)
    end
  end
end
