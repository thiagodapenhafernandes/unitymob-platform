require "rails_helper"

RSpec.describe Whatsapp::SyncTemplatesJob, type: :job do
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

    result = described_class.perform_now

    expect(result).to eq(ok: true, synced: 1)
    template = WhatsappTemplate.find_by!(name: "sample_template", language: "en_US")
    expect(template.header_format).to eq("text")
    expect(template.header_text).to eq("Hello")
    expect(template.template_type).to eq("text")
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

    described_class.perform_now

    template = WhatsappTemplate.find_by!(name: "weird_template")
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

    result = described_class.perform_now

    expect(result).to eq(ok: true, synced: 2)
    carousel = WhatsappTemplate.find_by!(name: "carousel_template")
    expect(carousel.template_type).to eq("carousel")
    expect(carousel.carousel_cards.map { |card| card["media_handle"] }).to eq(%w[handle-1 handle-2])

    flow = WhatsappTemplate.find_by!(name: "flow_template")
    expect(flow.template_type).to eq("flow")
    expect(flow.flow_config).to include("flow_id" => "123", "button_text" => "Abrir", "screen" => "START")
  end
end
