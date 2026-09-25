require "rails_helper"
require_relative "../../support/contract/shared_detail_examples"

RSpec.describe "contrato do detalhe público", type: :helper do
  def theme_partial_source(theme_key, name)
    partial = Tenant::PUBLIC_SITE_THEMES.fetch(theme_key).fetch(:components).fetch(name)
    dirname, _, basename = partial.rpartition("/")
    Rails.root.join("app/views", dirname, "_#{basename}.html.erb").read
  end

  let(:detail_standard_source) do
    Rails.root.join("app/views/habitations/show.html.erb").read +
      Rails.root.join("app/views/habitations/_price_card.html.erb").read +
      theme_partial_source("default", :detail_body)
  end
  let(:detail_luxury_source) do
    %w[property_gallery property_info property_contact_box property_map].map do |c|
      Rails.root.join("app/views/public_theme/components/_#{c}.html.erb").read
    end.join
  end

  it_behaves_like "contrato do detalhe público"
end
