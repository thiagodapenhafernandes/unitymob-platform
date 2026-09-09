require "rails_helper"
RSpec.describe Admin::WhatsappTemplatesHelper, type: :helper do
  it "formata texto sem permitir HTML executável" do
    rendered = helper.whatsapp_preview_text('*Olá* <script>alert(1)</script>')
    expect(rendered).to include('<strong>Olá</strong>')
    expect(rendered).not_to include('<script>')
  end
  it "aceita mídia HTTPS e recusa protocolos executáveis" do
    expect(helper.whatsapp_preview_media_url(nil, 'https://example.com/image.jpg')).to eq('https://example.com/image.jpg')
    expect(helper.whatsapp_preview_media_url(nil, 'javascript:alert(1)')).to be_nil
    expect(helper.whatsapp_preview_media_url(nil, '123456')).to be_nil
  end
end
