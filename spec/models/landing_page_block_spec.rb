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

    it "vazio é aceito (a prévia mostra o convite); link que não é do YouTube é recusado" do
      expect(block("video", {})).to be_valid
      invalid = block("video", { "url" => "https://vimeo.com/123" })
      expect(invalid).not_to be_valid
      expect(invalid.errors[:base].join).to include("YouTube")
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
      expect(LandingPages::BlockTypes.keys).to eq(%w[cover text property_showcase button image video embed])
      expect(LandingPages::BlockTypes.options.map(&:first)).to eq(["Capa", "Texto", "Vitrine de imóveis", "Botão", "Imagem", "Vídeo do YouTube", "Conteúdo incorporado (iframe)"])
      expect(LandingPages::BlockTypes::ALL.map { |definition| definition.fields.last.name }.uniq).to eq([:span])
    end

    it "recusa tipo desconhecido" do
      expect(block("script", { "x" => 1 })).not_to be_valid
    end
  end

  describe "dados" do
    it "guarda só os campos do tipo, com padrões e valores coagidos" do
      b = block("button", { "label" => "  Fale   conosco ", "url" => "#modal-fale-conosco", "style" => "hack", "extra" => "x", "new_tab" => "1" })
      b.valid?

      expect(b.data).to eq("label" => "Fale conosco", "url" => "#modal-fale-conosco", "style" => "primary", "align" => "center", "new_tab" => true, "span" => "full")
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
end
