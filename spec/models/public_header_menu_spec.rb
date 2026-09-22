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
end
