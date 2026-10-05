require "rails_helper"

RSpec.describe LandingPageBlock do
  let(:tenant) { Tenant.default }
  let(:page) { tenant.landing_pages.create!(title: "Página #{SecureRandom.hex(3)}", status: "draft") }

  def block(type, data = {}, **attrs)
    page.blocks.build({ block_type: type, position: 1, data: data }.merge(attrs))
  end

  it "bloco novo já traz os padrões do tipo (o editor mostra o valor certo)" do
    expect(LandingPageBlock.new(block_type: "property_showcase").data).to include("per_page" => 12, "visitor_filters" => true)
  end

  describe "vídeo do YouTube" do
    it "reconhece os formatos de link e o código de incorporar" do
      %w[
        https://www.youtube.com/watch?v=dQw4w9WgXcQ https://youtu.be/dQw4w9WgXcQ https://www.youtube.com/shorts/dQw4w9WgXcQ
        https://www.youtube.com/embed/dQw4w9WgXcQ https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ https://www.youtube.com/watch?feature=share&v=dQw4w9WgXcQ
      ].each { |url| expect(block("video", { "url" => url }).youtube_id).to eq("dQw4w9WgXcQ"), url }
      iframe = '<iframe width="560" src="https://www.youtube.com/embed/dQw4w9WgXcQ" title="x"></iframe>'
      expect(block("video", { "url" => iframe }).tap(&:valid?).youtube_id).to eq("dQw4w9WgXcQ")
    end

    it "vazio é aceito (a prévia mostra o convite); link que não é do YouTube ou Vimeo é recusado" do
      expect(block("video", {})).to be_valid
      invalid = block("video", { "url" => "https://example.com/123" })
      expect(invalid).not_to be_valid
      expect(invalid.errors[:base].join).to include("YouTube")
    end
  end


  describe "recursos institucionais" do
    it "aceita Vimeo comum e privado, mantendo apenas o hash necessário ao player" do
      expect(block("video", { "url" => "https://vimeo.com/123456789" }).video_embed_url).to eq("https://player.vimeo.com/video/123456789?dnt=1")
      expect(block("video", { "url" => "https://vimeo.com/123456789/abcdef1234" }).video_embed_url).to end_with("&h=abcdef1234")
      expect(block("video", { "url" => "https://player.vimeo.com/video/123456789?h=abcdef1234&autoplay=1" }).video_embed_url).to end_with("&h=abcdef1234")
      expect(block("video", { "url" => "https://vimeo.com.evil.test/123456789" })).not_to be_valid
    end

    it "normaliza os itens, limita a lista e descarta destinos, ícones e imagens inseguros" do
      item = { "title" => "Equipe", "image" => "javascript:alert(1)", "url" => "javascript:alert(1)", "icon" => 'people" onclick="x', "secret" => "x" }
      record = block("cards", { "items" => Array.new(60) { item } })
      expect(record.value(:items).size).to eq(50)
      expect(record.value(:items).first).to include("title" => "Equipe", "image" => "", "url" => "", "icon" => "")
      expect(record.value(:items).first).not_to have_key("secret")
      expect(block("cards", { "items" => ["invalid", ["bad"]] }).value(:items)).to eq([])
    end

    it "guarda colunas e aparência apenas dentro das opções suportadas" do
      section = block("section", { "columns" => 9, "background" => "javascript:x", "ratio" => "wide-first" })
      expect(section.value(:columns)).to eq(2)
      expect(section.value(:background)).to eq("plain")
      expect(section.value(:ratio)).to eq("wide-first")
    end
  end

  describe "conteúdo incorporado (iframe)" do
    it "aceita só https e extrai o endereço do código colado" do
      expect(block("embed", { "url" => "https://www.google.com/maps/embed?pb=1" })).to be_valid
      expect(block("embed", { "url" => '<iframe src="https://example.com/tour" width="600"></iframe>' }).tap(&:valid?).embed_url).to eq("https://example.com/tour")
      %w[http://example.com javascript:alert(1) data:text/html,x //example.com].each do |url|
        item = block("embed", { "url" => url })
        expect(item).not_to be_valid, url
      end
    end
  end

  describe "largura na linha" do
    it "full por padrão; 1 e 2 viram colunas; valor estranho volta a full" do
      expect(block("text", { "heading" => "x" }).tap(&:valid?).span).to be_nil
      expect(block("text", { "heading" => "x", "span" => "2" }).tap(&:valid?).span).to eq(2)
      expect(block("text", { "heading" => "x", "span" => "9" }).tap(&:valid?).span).to be_nil
    end
  end

  describe "catálogo de tipos" do
    it "tem os blocos de conteúdo, mídia e vitrine, todos com a largura na linha" do
      expect(LandingPages::BlockTypes.keys).to eq(%w[form cover text property_showcase button image video embed section cards indicators testimonials timeline partners team gallery])
      expect(LandingPages::BlockTypes.options.map(&:first)).to include("Vídeo (YouTube ou Vimeo)", "Seção com colunas", "Depoimentos", "Linha do tempo")
      LandingPages::BlockTypes::ALL.each do |definition|
        expect(definition.field(:column)).to be_present
        expect(definition.fields).to include(*LandingPages::BlockTypes::LAYOUT_FIELDS)
      end
    end

    it "recusa tipo desconhecido" do
      expect(block("script", { "x" => 1 })).not_to be_valid
    end
  end

  describe "dados" do
    it "limita deslocamentos, altura e camada e mantém mobile seguro por padrão" do
      b = block("text", { "heading" => "Teste", "offset_x" => 9999, "offset_y" => -9999, "layer" => 999, "layout_min_height" => 9999 })
      b.valid?
      expect(b.data.slice("offset_x", "offset_y", "layer", "layout_min_height", "mobile_layout")).to eq("offset_x" => 200, "offset_y" => -300, "layer" => 10, "layout_min_height" => 1200, "mobile_layout" => false)
    end
    it "guarda só os campos do tipo, com padrões e valores coagidos" do
      b = block("button", { "label" => "  Fale   conosco ", "url" => "#modal-fale-conosco", "style" => "hack", "extra" => "x", "new_tab" => "1", "text_color" => "red;background:url(x)", "icon" => "x\" onclick=x" })
      b.valid?

      expect(b.data.except(*LandingPages::BlockTypes::LAYOUT_FIELDS.map { |field| field.name.to_s })).to eq("label" => "Fale conosco", "url" => "#modal-fale-conosco", "style" => "primary", "align" => "center", "new_tab" => true, "span" => "full", "column" => "1", "icon" => "", "custom_colors" => false, "text_color" => "#ffffff", "background_color" => "#003344")
    end

    it "destino só aceita /página, http(s), mailto, tel e #modal-ID" do
      valid = %w[/contato https://exemplo.com mailto:a@b.com tel:+5547999 #modal-fale-conosco]
      valid.each { |url| expect(block("button", { "label" => "x", "url" => url })).to be_valid, url }

      ["javascript:alert(1)", "#contato", "data:text/html,x", "ftp://x"].each do |url|
        b = block("button", { "label" => "x", "url" => url })
        expect(b).not_to be_valid, url
        expect(b.data["url"]).to eq("")
      end
    end

    it "texto formatado é sanitizado (sem script nem on*), mantendo a formatação" do
      b = block("text", { "body" => '<p onclick="x()">oi <strong>você</strong></p><script>alert(1)</script><a href="javascript:x()">l</a>' })
      b.valid?

      expect(b.data["body"]).to include("<strong>você</strong>")
      expect(b.data["body"]).not_to include("script", "onclick", "javascript:")
    end

    it "capa usa o título da página quando vazio e limita o tamanho dos campos" do
      b = block("cover", { "title" => "t" * 500, "overlay" => 99, "align" => "diagonal" })
      b.valid?

      expect(b.data["title"].length).to eq(120)
      expect(b.data["overlay"]).to eq(45)
      expect(b.data["align"]).to eq("center")
    end

    it "vitrine guarda só filtros conhecidos, sem vazios, e opções válidas" do
      b = block("property_showcase", {
        "filters" => { "city" => ["", "Balneário Camboriú"], "category" => [""], "transaction_type" => "venda", "sql" => "1; drop", "characteristics" => ["frente_mar", ""] },
        "per_page" => "999", "sort" => "price_desc"
      })
      b.valid?

      expect(b.data["filters"]).to eq("city" => ["Balneário Camboriú"], "transaction_type" => "venda", "characteristics" => ["frente_mar"])
      expect(b.data["per_page"]).to eq(12)
      expect(b.data["sort"]).to eq("price_desc")
      expect(b.data["visitor_filters"]).to eq(true)
    end
  end

  describe "regras do tipo" do
    it "botão precisa de texto e destino; texto precisa de título ou corpo" do
      expect(block("button", { "label" => "", "url" => "/x" })).not_to be_valid
      expect(block("text", {})).not_to be_valid
      expect(block("text", { "heading" => "Sobre" })).to be_valid
      expect(block("cover", {})).to be_valid
    end

    it "herda a conta da página e não aceita outra conta" do
      b = block("cover")
      b.valid?
      expect(b.tenant_id).to eq(page.tenant_id)

      other = Tenant.create!(name: "Outra #{SecureRandom.hex(3)}", slug: "outra-#{SecureRandom.hex(3)}")
      expect(page.blocks.build(block_type: "cover", position: 2, tenant: other)).not_to be_valid
    end
  end
  it "não aceita copiar anexos de um bloco pertencente a outra página" do
    source = page.blocks.create!(block_type: "image", position: 0)
    other_page = tenant.landing_pages.create!(title: "Outra página")
    copy = other_page.blocks.build(block_type: "image", position: 0, copy_images_from: source.id)
    2.times { expect(copy).not_to be_valid }
    expect(copy.errors[:base]).to include("O bloco de origem deve pertencer a esta página")
  end

  it "mantém a rejeição de arquivo inválido em validações repetidas" do
    upload = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/template-video.mp4"), "video/mp4")
    record = block("gallery", { "items" => [{ "row_key" => "0", "title" => "Imagem" }] }, item_uploads: { "0" => upload })
    2.times { expect(record).not_to be_valid }
    expect(record.item_images).not_to be_attached
  end

end
