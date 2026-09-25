require "rails_helper"
require_relative "../../support/contract/shared_development_examples"

RSpec.describe "contrato do empreendimento público", type: :helper do
  let(:development_standard_source) do
    Rails.root.join("app/views/habitations/empreendimento_show.html.erb").read +
      Rails.root.join("app/views/empreendimentos/index.html.erb").read
  end
  let(:development_luxury_source) do
    (Dir[Rails.root.join("app/views/public_theme/components/_development_*.html.erb")].map { |f| File.read(f) } +
      [Rails.root.join("app/views/public_theme/_luxury_development_body.html.erb").read]).join
  end

  it_behaves_like "contrato do empreendimento público"
end
