# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "public_maps:geocode_missing" do
  include ActiveJob::TestHelper

  # Outros specs também chamam load_tasks; cada chamada acrescenta de novo as
  # ações da task e ela rodaria várias vezes. Começa de um registro limpo.
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  let(:tenant) { Tenant.create!(name: "Mapas", slug: "mapas-backfill") }
  let!(:missing) { create(:habitation, tenant: tenant, latitude: nil, longitude: nil) }
  let!(:located) { create(:habitation, tenant: tenant, latitude: -26.99, longitude: -48.63) }

  before do
    setting = instance_double(GoogleMapsIntegrationSetting, configured?: true, provider: "google")
    allow(GoogleMapsIntegrationSetting).to receive(:for).and_return(setting)
    ENV["TENANT"] = tenant.slug
    clear_enqueued_jobs
  end

  after do
    %w[TENANT APPLY].each { |key| ENV.delete(key) }
    Rake::Task["public_maps:geocode_missing"].reenable
  end

  it "só conta em dry run, sem enfileirar" do
    expect { Rake::Task["public_maps:geocode_missing"].invoke }
      .to output(/1 imóveis publicados sem coordenadas/).to_stdout
    expect(enqueued_jobs.count { |job| job[:job] == HabitationGeocodeJob }).to eq(0)
  end

  it "enfileira geocodificação só para quem está sem coordenadas com APPLY=1" do
    ENV["APPLY"] = "1"

    expect { Rake::Task["public_maps:geocode_missing"].invoke }.to output(/1 geocodificações enfileiradas/).to_stdout

    geocode_jobs = enqueued_jobs.select { |job| job[:job] == HabitationGeocodeJob }
    expect(geocode_jobs.map { |job| job[:args].first }).to eq([missing.id])
  end
end
