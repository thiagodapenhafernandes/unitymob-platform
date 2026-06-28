require "rails_helper"

RSpec.describe WhatsappTemplate, type: :model do
  describe "validacoes de midia" do
    it "aceita midia de cabecalho pendente antes de salvar" do
      template = described_class.new(
        name: "template_com_imagem",
        language: "pt_BR",
        category: "MARKETING",
        template_type: "text",
        body: "Olá, veja esta novidade.",
        header_format: "image"
      )

      template.header_media_file.attach(
        io: StringIO.new("fake-png"),
        filename: "exemplo.png",
        content_type: "image/png"
      )

      expect(template).to be_valid
    end
  end

  describe "normalizacao para Meta" do
    it "transforma nome de produto em identificador aceito pela Meta" do
      template = described_class.new(
        name: "Campanha Fake Julho",
        category: "MARKETING",
        body: "Olá"
      )

      template.valid?

      expect(template.name).to eq("campanha_fake_julho")
    end
  end

  describe "#components_payload" do
    it "monta cabecalho de video no formato esperado pela Meta" do
      template = described_class.new(
        name: "convite_video",
        category: "MARKETING",
        language: "pt_BR",
        body: "Olá {{1}}, veja o vídeo.",
        header_format: "video",
        header_media_handle: "meta-media-handle",
        example_values: ["Maria"]
      )

      expect(template.components_payload).to eq(
        [
          { type: "HEADER", format: "VIDEO", example: { header_handle: ["meta-media-handle"] } },
          { type: "BODY", text: "Olá {{1}}, veja o vídeo.", example: { body_text: [["Maria"]] } }
        ]
      )
    end

    it "usa apenas um handle de midia quando o parametro chega duplicado" do
      template = described_class.new(
        name: "convite_imagem",
        category: "MARKETING",
        language: "pt_BR",
        body: "Olá.",
        header_format: "image",
        header_media_handle: "handle-principal\r\nhandle-duplicado"
      )

      template.valid?

      expect(template.header_media_handle).to eq("handle-principal")
      expect(template.components_payload.first).to eq(
        { type: "HEADER", format: "IMAGE", example: { header_handle: ["handle-principal"] } }
      )
    end

    it "normaliza botoes para o componente BUTTONS" do
      template = described_class.new(
        name: "convite_botoes",
        category: "MARKETING",
        body: "Escolha uma opção.",
        buttons: {
          "0" => { "kind" => "quick_reply", "text" => "Saiba mais" },
          "1" => { "kind" => "url", "text" => "Abrir site", "url" => "https://example.com" },
          "2" => { "kind" => "phone_number", "text" => "Ligar", "url" => "+55 11 99999-0000" }
        }
      )

      expect(template.components_payload.last).to eq(
        {
          type: "BUTTONS",
          buttons: [
            { type: "QUICK_REPLY", text: "Saiba mais" },
            { type: "URL", text: "Abrir site", url: "https://example.com" },
            { type: "PHONE_NUMBER", text: "Ligar", phone_number: "+5511999990000" }
          ]
        }
      )
    end

    it "monta carrossel com cards de midia e botao" do
      template = described_class.new(
        name: "carrossel_lancamento",
        template_type: "carousel",
        category: "MARKETING",
        body: "Escolha uma opção.",
        carousel_cards: {
          "0" => { "media_type" => "image", "media_handle" => "handle-1", "text" => "Card 1", "button_kind" => "url", "button_text" => "Ver", "button_url" => "https://example.com/1" },
          "1" => { "media_type" => "video", "media_handle" => "handle-2", "text" => "Card 2", "button_kind" => "phone_number", "button_text" => "Ligar", "button_phone_number" => "+55 11 99999-0000" }
        }
      )

      expect(template.components_payload).to eq(
        [
          { type: "BODY", text: "Escolha uma opção." },
          {
            type: "CAROUSEL",
            cards: [
              {
                components: [
                  { type: "HEADER", format: "IMAGE", example: { header_handle: ["handle-1"] } },
                  { type: "BODY", text: "Card 1" },
                  { type: "BUTTONS", buttons: [{ type: "URL", text: "Ver", url: "https://example.com/1" }] }
                ]
              },
              {
                components: [
                  { type: "HEADER", format: "VIDEO", example: { header_handle: ["handle-2"] } },
                  { type: "BODY", text: "Card 2" },
                  { type: "BUTTONS", buttons: [{ type: "PHONE_NUMBER", text: "Ligar", phone_number: "+5511999990000" }] }
                ]
              }
            ]
          }
        ]
      )
    end

    it "permite resposta rapida em card de carrossel" do
      template = described_class.new(
        name: "carrossel_resposta",
        template_type: "carousel",
        category: "MARKETING",
        body: "Escolha.",
        carousel_cards: {
          "0" => { "media_type" => "image", "media_handle" => "handle-1", "text" => "Card 1", "button_kind" => "quick_reply", "button_text" => "Tenho interesse" },
          "1" => { "media_type" => "image", "media_handle" => "handle-2", "text" => "Card 2", "button_kind" => "url", "button_text" => "Ver", "button_url" => "https://example.com" }
        }
      )

      first_button = template.components_payload.last[:cards].first[:components].last[:buttons].first

      expect(first_button).to eq(type: "QUICK_REPLY", text: "Tenho interesse")
      expect(template).to be_valid
    end

    it "monta template com botao de Flow" do
      template = described_class.new(
        name: "flow_agendamento",
        template_type: "flow",
        category: "UTILITY",
        body: "Toque para agendar.",
        footer_text: "Leva menos de um minuto.",
        flow_config: {
          "flow_id" => "123456789",
          "button_text" => "Agendar",
          "action" => "navigate",
          "screen" => "APPOINTMENT"
        }
      )

      expect(template.components_payload).to eq(
        [
          { type: "BODY", text: "Toque para agendar." },
          { type: "FOOTER", text: "Leva menos de um minuto." },
          {
            type: "BUTTONS",
            buttons: [
              {
                type: "FLOW",
                text: "Agendar",
                flow_id: "123456789",
                flow_action: "NAVIGATE",
                navigate_screen: "APPOINTMENT"
              }
            ]
          }
        ]
      )
    end
  end

  describe "#interactive_buttons" do
    it "expoe botoes reais do template para campanhas e automacoes" do
      template = described_class.new(
        name: "convite_botoes",
        category: "MARKETING",
        body: "Escolha uma opção.",
        buttons: {
          "0" => { "kind" => "quick_reply", "text" => "Saiba mais" },
          "1" => { "kind" => "quick_reply", "text" => "Não tenho interesse" }
        }
      )

      expect(template.interactive_buttons.map { |button| button.slice("text", "kind", "actionable_reply") }).to eq(
        [
          { "text" => "Saiba mais", "kind" => "quick_reply", "actionable_reply" => true },
          { "text" => "Não tenho interesse", "kind" => "quick_reply", "actionable_reply" => true }
        ]
      )
    end

    it "expoe botoes de carrossel com contexto do card" do
      template = described_class.new(
        name: "carrossel_lancamento",
        template_type: "carousel",
        category: "MARKETING",
        body: "Escolha.",
        carousel_cards: {
          "0" => { "media_type" => "image", "media_handle" => "handle-1", "text" => "Card 1", "button_kind" => "quick_reply", "button_text" => "Tenho interesse" },
          "1" => { "media_type" => "image", "media_handle" => "handle-2", "text" => "Card 2", "button_kind" => "url", "button_text" => "Ver detalhes", "button_url" => "https://example.com" }
        }
      )

      expect(template.interactive_buttons.map { |button| button.slice("text", "kind", "context") }).to eq(
        [
          { "text" => "Tenho interesse", "kind" => "quick_reply", "context" => "Card 1" },
          { "text" => "Ver detalhes", "kind" => "url", "context" => "Card 2" }
        ]
      )
    end
  end
end
