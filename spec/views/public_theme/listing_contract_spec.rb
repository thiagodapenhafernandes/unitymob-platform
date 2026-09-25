require "rails_helper"
require_relative "../../support/contract/shared_listing_examples"

RSpec.describe "contrato da listagem pública", type: :helper do
  let(:listing_source) { Rails.root.join("app/views/habitations/index.html.erb").read }

  it_behaves_like "contrato da listagem pública"
end
