require "rails_helper"
require_relative "../../support/contract/shared_hero_examples"

RSpec.describe "contrato do hero público", type: :helper do
  let(:hero_standard_source) { Rails.root.join("app/views/home/_hero.html.erb").read }
  let(:hero_luxury_source) do
    Rails.root.join("app/views/public_theme/components/_hero.html.erb").read +
      Rails.root.join("app/views/public_theme/_luxury_home_hero.html.erb").read
  end

  it_behaves_like "contrato do hero público"
end
