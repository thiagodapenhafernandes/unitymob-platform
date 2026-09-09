require "rails_helper"
RSpec.describe BlogHelper, type: :helper do
  it "preserves selected text formatting after saving and sanitizes public font sizes" do
    article = Tenant.default.blog_articles.create!(title: "Formatado", content: '<p><u>Sublinhado</u> <strong>Negrito</strong> <em>Itálico</em> <u style="font-size: 1.25em">Maior</u> <span style="font-size: 0.85em">Menor</span> <a href="https://example.com">Link</a></p>')
    html, = helper.blog_article_body(article.reload)
    expect(html).to include('<u>Sublinhado</u>', '<strong>Negrito</strong>', '<em>Itálico</em>', 'class="ax-text-large"', 'class="ax-text-small"', 'href="https://example.com"')
    expect(html).not_to include('style=')
  end
  it "does not cache expiring Spaces links in article HTML" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("content"), filename: "example.png", content_type: "image/png", service_name: "test")
    allow(helper).to receive(:public_image_url).and_return("https://bucket.digitaloceanspaces.com/key?X-Amz-Signature=temporary")
    expect(helper.blog_image_url(blob, size: [640, 420])).to start_with("/rails/active_storage/blobs/proxy/")
  end
end
