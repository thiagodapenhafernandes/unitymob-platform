require "rails_helper"
require Rails.root.join("db/migrate/20260930130000_backfill_landing_page_blocks")

RSpec.describe BackfillLandingPageBlocks do
  let(:tenant) { Tenant.create!(name: "Backfill", slug: "backfill-#{SecureRandom.hex(3)}") }

  def run_up = ActiveRecord::Migration.suppress_messages { described_class.new.up }

  it "vira vitrine com os mesmos filtros (sem q/search) e texto SEO em bloco de Texto" do
    page = tenant.landing_pages.create!(title: "Antiga", filter_params: { "city" => ["Itajaí", ""], "q" => "praia", "min_bedrooms" => "3", "sort" => "x" }, content: "<p>Texto SEO</p>")

    run_up

    showcase, text = page.reload.blocks.ordered.to_a
    expect(showcase.block_type).to eq("property_showcase")
    expect(showcase.data["filters"]).to eq("city" => ["Itajaí"], "min_bedrooms" => "3")
    expect(showcase.data).to include("per_page" => 12, "visitor_filters" => true)
    expect(text).to have_attributes(block_type: "text")
    expect(text.data).to include("heading" => "Mais informações", "body" => "<p>Texto SEO</p>")
    expect(page.filter_params).to include("q" => "praia") # colunas antigas intactas
  end

  it "não cria bloco de texto sem conteúdo e não duplica ao rodar de novo" do
    page = tenant.landing_pages.create!(title: "Sem texto", filter_params: {})

    run_up
    run_up

    expect(page.reload.blocks.pluck(:block_type)).to eq(["property_showcase"])
  end

  it "não mexe em página que já tem blocos" do
    page = tenant.landing_pages.create!(title: "Nova", filter_params: { "city" => ["X"] })
    page.blocks.create!(block_type: "button", data: { "label" => "Oi", "url" => "/oi" })

    run_up

    expect(page.reload.blocks.pluck(:block_type)).to eq(["button"])
  end
end
