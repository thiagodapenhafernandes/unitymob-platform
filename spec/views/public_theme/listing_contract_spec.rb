require "rails_helper"
require_relative "../../support/contract/shared_listing_examples"

RSpec.describe "contrato da listagem pública", type: :helper do
  let(:listing_source) { Rails.root.join("app/views/habitations/index.html.erb").read.sub('render "listing_grid"', Rails.root.join("app/views/habitations/_listing_grid.html.erb").read).sub('render "listing_empty"', Rails.root.join("app/views/habitations/_listing_empty.html.erb").read) }

  it_behaves_like "contrato da listagem pública"
end
