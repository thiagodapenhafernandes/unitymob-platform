require "rails_helper"

RSpec.describe "public.js gated controllers" do
  let(:pack) { Rails.root.join("app/javascript/public.js").read }

  {
    "currency-mask" => "controllers/currency_mask_controller",
    "image-fallback" => "controllers/image_fallback_controller",
    "public-listing-nav" => "controllers/public_listing_nav_controller",
    "public-progressive-reveal" => "controllers/public_progressive_reveal_controller"
  }.each do |name, path|
    it "registra #{name} no pack público (gated)" do
      expect(pack).to include("[\"#{name}\", () => import(\"#{path}\")]")
      expect(Rails.root.join("app/javascript/#{path}.js")).to exist
    end
  end

  it "mantém a fiação data-controller nos campos de preço mínimo e máximo" do
    partial = Rails.root.join("app/views/habitations/_advanced_filters_fields.html.erb").read

    expect(partial.scan('controller: "currency-mask"').size).to eq(2)
    expect(partial).to include("input->currency-mask#format")
  end

  it "mantém a fiação data-controller na ordenação e grade da listagem" do
    index = Rails.root.join("app/views/habitations/index.html.erb").read.sub('render "listing_grid"', Rails.root.join("app/views/habitations/_listing_grid.html.erb").read)

    expect(index).to include("change->public-listing-nav#sort")
    expect(index).to include("click->public-listing-nav#follow")
  end

  it "mantém a fiação data-controller no reveal de unidades do empreendimento" do
    body = Rails.root.join("app/views/public_theme/components/_default_development_body.html.erb").read

    expect(body).to include('data-controller="public-progressive-reveal"')
  end

  it "mantém a fiação data-controller no logo do rodapé" do
    footer = Rails.root.join("app/views/public_theme/components/_site_footer.html.erb").read

    expect(footer).to include('controller: "image-fallback"')
  end

  it "não referencia controller inexistente no cabeçalho" do
    header = Rails.root.join("app/views/public_theme/components/_site_header.html.erb").read

    expect(header).not_to include("public-form-trigger")
    expect(header).not_to include("form_modal")
  end
end
