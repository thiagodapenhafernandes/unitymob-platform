require "rails_helper"

RSpec.describe Whatsapp::SyncTemplatesJob, type: :job do
  let(:tenant) { Tenant.create!(name: "Tenant templates #{SecureRandom.hex(3)}", slug: "tenant-templates-#{SecureRandom.hex(3)}") }
  let!(:integration) do
    tenant.whatsapp_business_integrations.create!(
      status: "connected",
      waba_id: "waba-sync",
      phone_number_id: "phone-sync",
      access_token: "token-sync"
    )
  end

  it "normaliza templates sincronizados com cabecalho de texto" do
    client = instance_double(Whatsapp::CloudClient)
    allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
    allow(client).to receive(:fetch_templates).and_return(
      ok: true,
      data: {
        "data" => [
          {
            "id" => "tpl_123",
            "name" => "sample_template",
            "language" => "en_US",
            "category" => "MARKETING",
            "status" => "APPROVED",
            "components" => [
              { "type" => "HEADER", "format" => "TEXT", "text" => "Hello" },
              { "type" => "BODY", "text" => "Hi {{1}}" }
            ]
          }
        ]
      }
    )

    result = described_class.perform_now(tenant.id)

    expect(result).to eq(ok: true, synced: 1)
    template = tenant.whatsapp_templates.find_by!(name: "sample_template", language: "en_US")
    expect(template.header_format).to eq("text")
    expect(template.header_text).to eq("Hello")
    expect(template.template_type).to eq("text")
  end

  it "sincroniza template aprovado com cabecalho de midia sem exigir anexo local" do
    client = instance_double(Whatsapp::CloudClient)
    allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
    allow(client).to receive(:fetch_templates).and_return(
      ok: true,
      data: {
        "data" => [
          {
            "id" => "tpl_image_123",
            "name" => "sample_image_template",
            "language" => "pt_BR",
            "category" => "MARKETING",
            "status" => "APPROVED",
            "components" => [
              { "type" => "HEADER", "format" => "IMAGE", "example" => { "header_handle" => ["meta-image-handle"] } },
              { "type" => "BODY", "text" => "Veja o imóvel {{1}}" }
            ]
          }
        ]
      }
    )

    result = described_class.perform_now(tenant.id)

    expect(result).to eq(ok: true, synced: 1)
    template = tenant.whatsapp_templates.find_by!(name: "sample_image_template", language: "pt_BR")
    expect(template).to have_attributes(
      status: "APPROVED",
      meta_id: "tpl_image_123",
      header_format: "image",
      header_media_handle: "meta-image-handle"
    )
    expect(template.header_media_file).not_to be_attached
  end

  it "baixa e anexa a midia de exemplo quando o cabecalho sincronizado vem com URL" do
    client = instance_double(Whatsapp::CloudClient)
    media_response = instance_double(
      HTTParty::Response,
      success?: true,
      body: "fake-image-content",
      headers: { "content-type" => "image/png" }
    )

    allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
    allow(client).to receive(:fetch_templates).and_return(
      ok: true,
      data: {
        "data" => [
          {
            "id" => "tpl_image_url_123",
            "name" => "sample_image_url_template",
            "language" => "pt_BR",
            "category" => "MARKETING",
            "status" => "APPROVED",
            "components" => [
              { "type" => "HEADER", "format" => "IMAGE", "example" => { "header_handle" => ["https://scontent.whatsapp.net/media/header.png?oh=123"] } },
              { "type" => "BODY", "text" => "Veja o imóvel {{1}}" }
            ]
          }
        ]
      }
    )
    allow(HTTParty).to receive(:get).with("https://scontent.whatsapp.net/media/header.png?oh=123", timeout: 30).and_return(media_response)

    result = described_class.perform_now(tenant.id)

    expect(result).to eq(ok: true, synced: 1)
    template = tenant.whatsapp_templates.find_by!(name: "sample_image_url_template", language: "pt_BR")
    expect(template.header_media_file).to be_attached
    expect(template.header_media_file.blob.filename.to_s).to eq("header.png")
    expect(template.header_media_file.blob).to have_attributes(content_type: "image/png", byte_size: "fake-image-content".bytesize)
  end

  it "usa defaults seguros quando a API retornar formato inesperado" do
    client = instance_double(Whatsapp::CloudClient)
    allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
    allow(client).to receive(:fetch_templates).and_return(
      ok: true,
      data: {
        "data" => [
          {
            "name" => "weird_template",
            "components" => [
              { "type" => "HEADER", "format" => "LOCATION" },
              { "type" => "BODY", "text" => "Mensagem" }
            ]
          }
        ]
      }
    )

    described_class.perform_now(tenant.id)

    template = tenant.whatsapp_templates.find_by!(name: "weird_template")
    expect(template.header_format).to eq("none")
    expect(template.category).to eq("MARKETING")
    expect(template.status).to eq("PENDING")
  end

  it "preenche dados editaveis de carousel e flow ao sincronizar" do
    client = instance_double(Whatsapp::CloudClient)
    allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
    allow(client).to receive(:fetch_templates).and_return(
      ok: true,
      data: {
        "data" => [
          {
            "id" => "carousel_123",
            "name" => "carousel_template",
            "language" => "pt_BR",
            "category" => "MARKETING",
            "status" => "APPROVED",
            "components" => [
              { "type" => "BODY", "text" => "Escolha uma opção." },
              {
                "type" => "CAROUSEL",
                "cards" => [
                  {
                    "components" => [
                      { "type" => "HEADER", "format" => "IMAGE", "example" => { "header_handle" => ["handle-1"] } },
                      { "type" => "BODY", "text" => "Card 1" },
                      { "type" => "BUTTONS", "buttons" => [{ "type" => "URL", "text" => "Ver", "url" => "https://example.com/1" }] }
                    ]
                  },
                  {
                    "components" => [
                      { "type" => "HEADER", "format" => "IMAGE", "example" => { "header_handle" => ["handle-2"] } },
                      { "type" => "BODY", "text" => "Card 2" },
                      { "type" => "BUTTONS", "buttons" => [{ "type" => "URL", "text" => "Abrir", "url" => "https://example.com/2" }] }
                    ]
                  }
                ]
              }
            ]
          },
          {
            "id" => "flow_123",
            "name" => "flow_template",
            "language" => "pt_BR",
            "category" => "UTILITY",
            "status" => "APPROVED",
            "components" => [
              { "type" => "BODY", "text" => "Abra o formulário." },
              { "type" => "BUTTONS", "buttons" => [{ "type" => "FLOW", "text" => "Abrir", "flow_id" => "123", "flow_action" => "NAVIGATE", "navigate_screen" => "START" }] }
            ]
          }
        ]
      }
    )

    result = described_class.perform_now(tenant.id)

    expect(result).to eq(ok: true, synced: 2)
    carousel = tenant.whatsapp_templates.find_by!(name: "carousel_template")
    expect(carousel.template_type).to eq("carousel")
    expect(carousel.carousel_cards.map { |card| card["media_handle"] }).to eq(%w[handle-1 handle-2])

    flow = tenant.whatsapp_templates.find_by!(name: "flow_template")
    expect(flow.template_type).to eq("flow")
    expect(flow.flow_config).to include("flow_id" => "123", "button_text" => "Abrir", "screen" => "START")
  end

  it "agenda fan-out para integrações conectadas quando nenhum tenant é informado" do
    allow(Whatsapp::CloudClient).to receive(:new)

    result = described_class.perform_now

    expect(result[:ok]).to be(true)
    expect(result[:enqueued]).to be >= 1
    expect(Whatsapp::CloudClient).not_to have_received(:new)
  end
end
