require "rails_helper"

RSpec.describe LandingPagesHelper, type: :helper do
  it "aplica cores de ações somente quando ativadas e válidas" do
    data = { "button_custom_colors" => true, "button_background_color" => "#123456", "button_text_color" => "#ffffff" }
    expect(helper.landing_page_action_color_style(data)).to eq("background-color:#123456;border-color:#123456;color:#ffffff")
    expect(helper.landing_page_action_color_style(data, "secondary")).to be_nil
    expect(helper.landing_page_action_color_style(data.merge("button_custom_colors" => false))).to be_nil
    expect(helper.landing_page_action_color_style(data.merge("button_text_color" => "red;display:none"))).to be_nil
  end

  it "limita bordas e rejeita estilos arbitrários" do
    data = { "button_custom_border" => true, "button_border_color" => "#123456", "button_border_style" => "solid", "button_border_width" => 99, "button_border_radius" => -1 }
    expect(helper.landing_page_border_style(data, "button")).to eq("border:12px solid #123456;border-radius:0px")
    expect(helper.landing_page_border_style(data.merge("button_border_style" => "bad"), "button")).to be_nil
  end

  it "emite cores opt-in no bloco sem aceitar CSS arbitrário" do
    block = LandingPageBlock.new(block_type: "text", data: { block_custom_colors: true, block_background_color: "#112233", block_text_color: "#abcdef" })
    attributes = helper.landing_page_layout_attributes(block)
    expect(attributes[:class]).to include("has-custom-colors")
    expect(attributes[:style]).to include("--lp-custom-background:#112233", "--lp-custom-text:#abcdef")
    block.data["block_custom_colors"] = false
    expect(helper.landing_page_layout_attributes(block)[:style]).not_to include("--lp-custom-background")
  end

  it "disponibiliza cores do bloco em todos os tipos sem ativar por padrão" do
    LandingPages::BlockTypes.keys.each do |type|
      definition = LandingPages::BlockTypes.find(type)
      expect(definition.normalize({})["block_custom_colors"]).to eq(false)
      normalized = definition.normalize("block_custom_colors" => true, "block_background_color" => "invalid", "block_text_color" => "#123456")
      expect(normalized["block_background_color"]).to eq("#ffffff")
      expect(normalized["block_text_color"]).to eq("#123456")
    end
  end

  it "escolhe a cor de maior contraste para superfícies da marca" do
    { "#ffffff" => "#000000", "#ffee00" => "#000000", "#003344" => "#ffffff", "invalid" => "#ffffff" }.each do |color, ink|
      helper.instance_variable_set(:@layout_setting, OpenStruct.new(primary_color: color))
      expect(helper.landing_page_brand_ink).to eq(ink)
    end
  end
  it "ordena elementos irmãos mantendo containers e conteúdo não editável" do
    block = LandingPageBlock.new(block_type: "cover", data: { element_order: "badge,title,subtitle,eyebrow" })
    html = '<section><div><span data-element-field="eyebrow">Etiqueta</span><h1 data-element-field="title">Título</h1><p data-element-field="subtitle">Texto</p><span data-element-field="badge">Selo</span><aside>Preservado</aside></div></section>'
    result = Nokogiri::HTML.fragment(helper.landing_page_order_elements(html.html_safe, block))
    expect(result.css('[data-element-field]').map { |node| node['data-element-field'] }).to eq(%w[badge title subtitle eyebrow])
    expect(result.at_css('section > div > aside').text).to eq('Preservado')
    block.data['element_order'] = ''
    expect(helper.landing_page_order_elements(html, block)).to eq(html)
  end

  it "aplica fundos transparentes e gradientes sem aceitar CSS livre" do
    style = { "element_text_background_mode" => "gradient", "element_text_background_color" => "#112233", "element_text_gradient_color" => "#abcdef", "element_text_background_opacity" => 50, "element_text_gradient_angle" => 999 }
    expect(helper.landing_page_creative_style(style, "element_text")).to include("linear-gradient(360deg,rgba(17,34,51,0.5),rgba(171,205,239,0.5))")
    expect(helper.landing_page_creative_style(style.merge("element_text_background_color" => "red;display:none"), "element_text")).to be_nil
    expect(helper.landing_page_creative_style(style.merge("element_text_background_mode" => "transparent"), "element_text")).to eq("background:transparent")
  end

  it "limita tipografia e vidro, preservando a aparência quando não configurados" do
    expect(helper.landing_page_creative_style({})).to be_nil
    data = { "block_font_family" => "georgia", "block_font_size" => 999, "block_font_weight" => "700;display:none", "block_font_style" => "italic", "block_backdrop_enabled" => true, "block_backdrop_blur" => 99, "block_backdrop_saturation" => -2 }
    expect(helper.landing_page_creative_style(data)).to include("font-family:Georgia,serif", "font-size:120px", "font-style:italic", "blur(40px) saturate(0%)")
    expect(helper.landing_page_creative_style(data)).not_to include("display", "font-weight")
  end

  it "normaliza os estilos do card e do texto independentemente e ignora itens vazios" do
    definition = LandingPages::BlockTypes.fetch("cards")
    normalized = definition.normalize("items" => [{ "title" => "Propósito", "background_mode" => "gradient", "element_text_font_family" => "georgia", "element_text_text_gradient" => "true" }, {}])
    expect(normalized["items"].length).to eq(1)
    expect(normalized["items"].first).to include("background_mode" => "gradient", "background_opacity" => 100, "element_text_font_family" => "georgia", "element_text_text_gradient" => true)
    expect(normalized["items"].first["element_title_font_family"]).to eq("inherit")
    expect(normalized["block_background_mode"]).to eq("inherit")
    expect(definition.normalize("block_font_size" => { "invalid" => 20 })["block_font_size"]).to eq(0)
  end

  it "não reordena os elementos de um bloco filho ao ordenar a seção" do
    block = LandingPageBlock.new(block_type: "section", data: { element_order: "subtitle,heading" })
    html = '<section><header><h2 data-element-field="heading">Seção</h2><p data-element-field="subtitle">Subtítulo</p></header><div class="public-theme-block-layout"><h2 data-element-field="heading">Filho</h2><p data-element-field="subtitle">Texto filho</p></div></section>'
    result = Nokogiri::HTML.fragment(helper.landing_page_order_elements(html, block))
    expect(result.css('header [data-element-field]').map { |node| node['data-element-field'] }).to eq(%w[subtitle heading])
    expect(result.css('.public-theme-block-layout [data-element-field]').map { |node| node['data-element-field'] }).to eq(%w[heading subtitle])
  end

  it "preserva a formatação semântica do Trix e remove scripts e CSS livre" do
    data = LandingPages::BlockTypes.fetch("text").normalize("body" => '<p><strong>Negrito</strong> <em>Itálico</em> <del>Riscado</del></p><pre><code>Exemplo</code></pre><script>alert(1)</script><p style="display:none">Texto</p>')
    expect(data["body"]).to include('<strong>Negrito</strong>', '<em>Itálico</em>', '<del>Riscado</del>', '<pre><code>Exemplo</code></pre>')
    expect(data["body"]).not_to include('<script', 'style=')
  end

end

RSpec.describe LandingPagesHelper, type: :helper do
  it 'keeps callout surface styles on the rounded card instead of its outer layout' do
    allow(helper).to receive(:landing_page_brand_ink).and_return('#ffffff')
    block = LandingPageBlock.new(block_type: 'callout', data: { 'block_custom_colors' => true, 'block_background_color' => '#bb4444', 'block_text_color' => '#ffffff', 'block_background_mode' => 'solid', 'block_custom_border' => true, 'block_border_color' => '#bb4444', 'block_border_style' => 'solid', 'block_border_width' => 1, 'block_border_radius' => 18 })
    attributes = helper.landing_page_layout_attributes(block)
    expect(attributes[:style]).not_to include('--lp-custom-background', '--lp-style-background:', 'border-radius:')
    surface = helper.landing_page_action_color_style(block.data, 'block')
    expect(surface).to include('background:rgba(187,68,68,1.0)', 'border-radius:18px')
  end
end
