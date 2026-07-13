require "rails_helper"

RSpec.describe "Public habitations mobile listing contract" do
  let(:view_source) { Rails.root.join("app/views/habitations/index.html.erb").read }
  let(:style_source) { Rails.root.join("app/assets/stylesheets/public_habitations_index_refresh.css").read }

  it "renders results before SEO and related-search content" do
    grid_position = view_source.index("public-habitations-index__grid")
    pagination_position = view_source.index("public-habitations-index__pagination")
    seo_position = view_source.index("public-habitations-index__seo-intro")
    related_position = view_source.index("public-habitations-index__strategic-links")

    expect(grid_position).to be < pagination_position
    expect(pagination_position).to be < seo_position
    expect(pagination_position).to be < related_position
  end

  it "provides a full-screen mobile filter and compact result toolbar" do
    expect(view_source).to include('aria-modal="true"')
    expect(view_source).to include("public-habitations-index__title-mobile")
    expect(style_source).to match(/@media \(max-width: 640px\).*?\.public-habitations-index__drawer \{.*?height: 100dvh;/m)
    expect(style_source).to match(/@media \(max-width: 640px\).*?\.public-habitations-index__filterbar \{\s*display: none;/m)
    expect(style_source).to match(/\.public-habitations-index__floating-filter \{.*?left: 50%;.*?transform: translateX\(-50%\);/m)
  end

  it "keeps desktop quick filters and clear action on a single row" do
    expect(view_source).to include("public-habitations-index__quick-scroll")
    expect(view_source).to include("public-habitations-index__clear-link flex flex-none")
    expect(style_source).to match(/\.public-habitations-index__quick-row \{.*?flex-wrap: nowrap;/m)
    expect(style_source).to match(/\.public-habitations-index__quick-scroll \{.*?overflow-x: auto;/m)
  end
end
