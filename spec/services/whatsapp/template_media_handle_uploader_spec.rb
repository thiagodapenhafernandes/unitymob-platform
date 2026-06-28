require "rails_helper"

RSpec.describe Whatsapp::TemplateMediaHandleUploader do
  it "envia midia de cabecalho pendente para gerar handle da Meta" do
    template = WhatsappTemplate.new(
      name: "template_imagem",
      language: "pt_BR",
      category: "MARKETING",
      template_type: "text",
      body: "Olá",
      header_format: "image"
    )
    template.header_media_file.attach(
      io: StringIO.new("fake-image"),
      filename: "exemplo.png",
      content_type: "image/png"
    )
    client = instance_double(Whatsapp::CloudClient)
    allow(client).to receive(:upload_template_media).and_return({ ok: true, handle: "handle-imagem" })

    result = described_class.call(template: template, client: client)

    expect(result).to eq(ok: true, handle: "handle-imagem")
    expect(client).to have_received(:upload_template_media).with(
      hash_including(file_name: "exemplo.png", content_type: "image/png", byte_size: 10)
    )
  end
end
