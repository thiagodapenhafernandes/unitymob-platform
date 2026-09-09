require "rails_helper"

RSpec.describe Admin::UiHelper, type: :helper do
  it "supplies stable image URLs for imported attachments without changing stored content" do
    blob = ActiveStorage::Blob.create_and_upload!(io: File.open(Rails.root.join("spec/fixtures/files/watermark.png")), filename: "photo.png", content_type: "image/png", service_name: "test", metadata: { tenant_id: Tenant.default.id, purpose: "blog" })
    article = Tenant.default.blog_articles.create!(title: "Com imagem", content: ActionText::Attachment.from_attachable(blob, caption: "Vista da cidade").to_html)
    original = article.content.body.to_html
    html = helper.ax_rich_text_editor_value(article.content)
    attributes = JSON.parse(Nokogiri::HTML.fragment(html).at_css("[data-trix-attachment]")["data-trix-attachment"])
    expect(attributes.fetch("url")).to start_with("/rails/active_storage/blobs/proxy/")
    expect(attributes.fetch("href")).to eq(attributes.fetch("url"))
    expect(html).to include("Vista da cidade")
    expect(article.reload.content.body.to_html).to eq(original)
  end
end
