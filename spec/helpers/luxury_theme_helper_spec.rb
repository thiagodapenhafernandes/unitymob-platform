require "rails_helper"

RSpec.describe LuxuryThemeHelper, type: :helper do
  let(:entry_class) { Struct.new(:label, :url, :icon, :new_tab) }

  it "mapeia entradas do menu para o formato luxury" do
    items = helper.luxury_nav_items([
      entry_class.new("Comprar", "/imoveis", nil, false),
      entry_class.new("Blog", "https://blog.ex", "globe", true),
      entry_class.new("", "/vazio", nil, false)
    ])

    expect(items).to eq([
      { label: "Comprar", url: "/imoveis" },
      { label: "Blog", url: "https://blog.ex", icon: "globe", target: "_blank", rel: "noopener" }
    ])
  end
end

RSpec.describe LuxuryThemeHelper, type: :helper do
  let(:bar_entry_class) { Struct.new(:label, :url, :icon, :new_tab, :bar) { alias_method :bar?, :bar } }

  FakeVariant = Struct.new(:value)

  FakeLogo = Struct.new(:attached, :content_type, :variant_behavior) do
    alias_method :attached?, :attached
    def variant(*)
      raise StandardError, "vips" if variant_behavior == :raise

      FakeVariant.new(variant_behavior)
    end
  end

  FakeLayout = Struct.new(:logo)

  it "bar_only espelha o header padrao: so itens bar? na barra" do
    entries = [
      bar_entry_class.new("Comprar", "/imoveis", nil, false, true),
      bar_entry_class.new("Parceria", "/parceria", nil, false, false)
    ]

    expect(helper.luxury_nav_items(entries, bar_only: true).map { |i| i[:label] }).to eq(["Comprar"])
    expect(helper.luxury_nav_items(entries).map { |i| i[:label] }).to eq(%w[Comprar Parceria])
  end

  it "logo usa a variante e cai para o original quando ela falha" do
    ok = FakeLogo.new(true, "image/png", "VARIANT")
    expect(helper.luxury_logo(FakeLayout.new(ok))).to eq(FakeVariant.new("VARIANT"))

    broken = FakeLogo.new(true, "image/png", :raise)
    expect(helper.luxury_logo(FakeLayout.new(broken))).to eq(broken)

    svg = FakeLogo.new(true, "image/svg+xml", :raise)
    expect(helper.luxury_logo(FakeLayout.new(svg))).to eq(svg)

    expect(helper.luxury_logo(FakeLayout.new(FakeLogo.new(false, "image/png", "X")))).to be_nil
    expect(helper.luxury_logo(nil)).to be_nil
  end
end
