require "rails_helper"
require_relative "../../support/contract/shared_property_card_examples"

RSpec.describe "public_theme/components/_property_card.html.erb", type: :view do
  let(:card_partial) { "public_theme/components/property_card" }
  let(:card_variant) { "salute-luxury" }

  it_behaves_like "contrato do card público"
end
