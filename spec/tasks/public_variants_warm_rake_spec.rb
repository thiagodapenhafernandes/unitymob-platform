# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "images:warm_public_variants" do
  before(:all) do
    Rails.application.load_tasks
  end

  after do
    ENV.delete("LIMIT")
    ENV.delete("DRY_RUN")
    Rake::Task["images:warm_public_variants"].reenable
  end

  it "roda em dry-run sem processar nada" do
    create(:habitation, codigo: "WARM-1")

    expect {
      ENV["LIMIT"] = "10"
      ENV["DRY_RUN"] = "true"
      Rake::Task["images:warm_public_variants"].invoke
    }.to output(/warm_public_variants: 1 imóveis, 0 resoluções \(dry run\)/).to_stdout
  end
end
