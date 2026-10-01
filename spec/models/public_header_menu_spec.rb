require "rails_helper"

RSpec.describe PublicHeaderMenu do
  it "sem personalização entrega os itens do sistema e a barra original" do
    entries = described_class.entries([], blog_url: "/blog")

    expect(entries.map(&:key)).to eq(described_class::SYSTEM_ITEMS.keys)
    expect(entries.select(&:bar?).map(&:label)).to eq(%w[Comprar Alugar Anunciar Empreendimentos Lançamentos Blog Favoritos])
  end

  it "esconde itens que dependem de dado ausente e mantém a ordem gravada" do
    saved = [{ "key" => "contato" }, { "key" => "blog" }, { "key" => "comprar", "label" => "Quero comprar" }]
    visible = described_class.visible(saved, blog_url: nil, youtube_url: nil)

    expect(visible.first(2).map(&:key)).to eq(%w[contato comprar])
    expect(visible[1].label).to eq("Quero comprar")
    expect(visible.map(&:key)).not_to include("blog", "youtube")
  end

  it "marca o item ativo pela página em que o visitante está" do
    context = described_class::Context.new(controller_name: "habitations", params: { transaction_type: "venda" })

    active = described_class.entries([], context: context).select(&:active?).map(&:key)

    expect(active).to eq(["comprar"])
  end

  it "sanitiza o que vem do formulário" do
    result = described_class.normalize(
      "0" => { "key" => "inventado", "label" => "x" },
      "1" => { "key" => "custom-1", "label" => "Ok", "url" => "/ok", "position" => "1" },
      "2" => { "key" => "custom-2", "label" => "Ruim", "url" => "javascript:alert(1)" },
      "3" => { "key" => "custom-3", "label" => "", "url" => "/sem-nome" }
    )

    expect(result.map { |item| item["key"] }).to eq(["custom-1"])
  end

  it "aceita gatilho de modal namespaced e recusa fragmento solto" do
    result = described_class.normalize(
      "0" => { "key" => "custom-1", "label" => "Anunciar", "url" => "#modal-anuncie-seu-imovel", "position" => "1" },
      "1" => { "key" => "custom-2", "label" => "Âncora", "url" => "#contato", "position" => "2" }
    )

    expect(result.map { |item| item["key"] }).to eq(["custom-1"])
  end

  describe "endereço próprio nos itens do sistema" do
    it "guarda o endereço informado (inclusive #modal-ID) e ignora vazio, inválido ou igual ao padrão" do
      result = described_class.normalize(
        "0" => { "key" => "trabalhe", "url" => "#modal-trabalhe-conosco", "position" => "1" },
        "1" => { "key" => "sobre", "url" => "", "position" => "2" },
        "2" => { "key" => "contato", "url" => "javascript:alert(1)", "position" => "3" },
        "3" => { "key" => "parceria", "url" => Rails.application.routes.url_helpers.parcerias_path, "position" => "4" },
        "4" => { "key" => "home", "url" => "https://exemplo.com.br/promo", "position" => "5" }
      )
      by_key = result.to_h { |item| [item["key"], item] }

      expect(by_key["trabalhe"]["url"]).to eq("#modal-trabalhe-conosco")
      expect(by_key["home"]["url"]).to eq("https://exemplo.com.br/promo")
      expect(by_key["sobre"]).not_to include("url")
      expect(by_key["contato"]).not_to include("url")
      expect(by_key["parceria"]).not_to include("url")
    end

    it "a entrada usa o endereço próprio e mantém o padrão da página para sugestão" do
      entry = described_class.entries([{ "key" => "trabalhe", "url" => "#modal-trabalhe-conosco" }]).find { |e| e.key == "trabalhe" }

      expect(entry.url).to eq("#modal-trabalhe-conosco")
      expect(entry.default_url).to eq(Rails.application.routes.url_helpers.trabalhe_conosco_path)
      expect(entry.custom?).to eq(false)
    end

    it "sem endereço próprio (ou inválido) segue o padrão do sistema" do
      path = Rails.application.routes.url_helpers.trabalhe_conosco_path

      expect(described_class.entries([]).find { |e| e.key == "trabalhe" }.url).to eq(path)
      expect(described_class.entries([{ "key" => "trabalhe", "url" => "  javascript:x" }]).find { |e| e.key == "trabalhe" }.url).to eq(path)
    end

    it "item que depende de dado ausente aparece quando tem endereço próprio" do
      hidden = described_class.visible([], blog_url: nil)
      shown = described_class.visible([{ "key" => "blog", "url" => "/meu-blog" }], blog_url: nil)

      expect(hidden.map(&:key)).not_to include("blog")
      expect(shown.find { |e| e.key == "blog" }.url).to eq("/meu-blog")
    end
  end

  describe "nova aba nos itens do sistema" do
    it "guarda só quando difere do padrão do item" do
      result = described_class.normalize(
        "0" => { "key" => "sobre", "new_tab" => "1", "position" => "1" },
        "1" => { "key" => "contato", "new_tab" => "0", "position" => "2" },
        "2" => { "key" => "youtube", "new_tab" => "0", "position" => "3" },
        "3" => { "key" => "links_uteis", "new_tab" => "1", "url" => "", "position" => "4" }
      ).to_h { |item| [item["key"], item] }

      expect(result["sobre"]["new_tab"]).to eq(true)
      expect(result["contato"]).not_to include("new_tab")
      expect(result["youtube"]["new_tab"]).to eq(false)
      expect(result["links_uteis"]["new_tab"]).to eq(true)
    end

    it "a entrada respeita o que foi gravado e mantém o padrão quando nada foi gravado" do
      entries = described_class.entries([{ "key" => "sobre", "new_tab" => true }, { "key" => "youtube", "new_tab" => false }], youtube_url: "https://youtube.com/c/x")
      by_key = entries.index_by(&:key)

      expect(by_key["sobre"].new_tab).to eq(true)
      expect(by_key["youtube"].new_tab).to eq(false)
      expect(by_key["contato"].new_tab).to eq(false)
      expect(described_class.entries([], youtube_url: "https://youtube.com/c/x").find { |e| e.key == "youtube" }.new_tab).to eq(true)
    end
  end
end
