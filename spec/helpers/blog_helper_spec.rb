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
    expect(helper).not_to receive(:public_image_url)
    expect(blob.service).not_to receive(:exist?)
    expect(blob.service).not_to receive(:download)
    expect(helper.blog_image_url(blob, size: [640, 420])).to start_with("/rails/active_storage/representations/proxy/")
  end
  it "prioritizes responsive covers and leaves secondary images lazy" do
    blob = ActiveStorage::Blob.create_and_upload!(io: File.open(Rails.root.join("spec/fixtures/files/watermark.png")), filename: "cover.png", content_type: "image/png", service_name: "test", metadata: { tenant_id: Tenant.default.id, purpose: "blog" })
    article = nil
    expect {
      article = Tenant.default.blog_articles.create!(title: "Capa", cover: blob)
    }.to have_enqueued_job(ActiveStorage::TransformJob).at_least(:once)
    hero = Nokogiri::HTML.fragment(helper.blog_cover(article, hero: true)).at_css("img")
    expect(hero["loading"]).to eq("eager")
    expect(hero["fetchpriority"]).to eq("high")
    expect(hero["srcset"]).to include("640w", "1600w")
    expect(hero["decoding"]).to eq("async")
    card = Nokogiri::HTML.fragment(helper.blog_cover(article)).at_css("img")
    expect(card["loading"]).to eq("lazy")
    article.content = ActionText::Attachment.from_attachable(blob).to_html
    article.save!
    body, = helper.blog_article_body(article)
    expect(Nokogiri::HTML.fragment(body).at_css("img")["loading"]).to eq("lazy")
  end

end
