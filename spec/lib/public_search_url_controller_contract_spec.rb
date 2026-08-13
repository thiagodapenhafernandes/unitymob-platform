require "rails_helper"

RSpec.describe "public_search_url_controller.js" do
  let(:source) { Rails.root.join("app/javascript/controllers/public_search_url_controller.js").read }

  it "gera URLs amigáveis preservando filtros avançados em query string" do
    expect(source).to include(
      'const FRIENDLY_KEYS = new Set',
      '"/imoveis"',
      '"category[]"',
      '"city[]"',
      '"characteristics[]"',
      'segments.push(this.segmentFor(categories))',
      'query.append(key, cleaned)'
    )
  end
end
