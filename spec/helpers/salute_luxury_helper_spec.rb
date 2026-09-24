require "rails_helper"

RSpec.describe SaluteLuxuryHelper, type: :helper do
  let(:entry_class) { Struct.new(:label, :url, :icon, :new_tab) }

  it "mapeia entradas do menu para o formato luxury" do
    items = helper.salute_luxury_nav_items([
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
