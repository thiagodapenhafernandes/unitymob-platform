require "rails_helper"

RSpec.describe Geo::AddressGeocoder do
  let(:geocoder) do
    described_class.new(address: "Av. Brasil", number: "1", neighborhood: "Centro", city: "Balneário Camboriú",
                        state: "SC", zip_code: "88330000", api_key: "chave")
  end

  it "expõe e registra no log a recusa do Google em vez de falhar calado" do
    allow(geocoder).to receive(:json_get).and_return(
      "status" => "REQUEST_DENIED", "error_message" => "API keys with referer restrictions cannot be used with this API."
    )
    allow(Rails.logger).to receive(:warn)

    expect(geocoder.call).to be_nil
    expect(geocoder.google_status).to eq("REQUEST_DENIED")
    expect(geocoder.google_error).to include("referer restrictions")
    expect(Rails.logger).to have_received(:warn).with(/google_request_denied/)
  end

  it "endereço não encontrado não é tratado como erro de configuração" do
    allow(geocoder).to receive(:json_get).and_return("status" => "ZERO_RESULTS", "results" => [])
    allow(Rails.logger).to receive(:warn)

    expect(geocoder.call).to be_nil
    expect(geocoder.google_status).to eq("ZERO_RESULTS")
    expect(Rails.logger).not_to have_received(:warn)
  end

  it "no modo leaflet usa só o OpenStreetMap, mesmo com chave Google no ambiente" do
    leaflet = described_class.new(address: "Av. Brasil", number: "1", neighborhood: "Centro", city: "Itajaí",
                                  state: "SC", zip_code: "", provider: "leaflet")
    allow(leaflet).to receive(:sleep)
    allow(leaflet).to receive(:json_get) do |url, _params|
      raise "não deveria chamar o Google" if url.include?("googleapis")

      [{ "lat" => "-26.9", "lon" => "-48.6", "display_name" => "Av. Brasil", "address" => { "house_number" => "1" } }]
    end

    previous = ENV["GOOGLE_MAPS_API_KEY"]
    ENV["GOOGLE_MAPS_API_KEY"] = "chave-do-ambiente"

    expect(leaflet.call.provider).to eq("osm")
  ensure
    ENV["GOOGLE_MAPS_API_KEY"] = previous
  end

  describe "#neighborhood_call" do
    let(:neighborhood_geocoder) do
      described_class.new(address: "Rua Nova", number: "1", neighborhood: "Praia Brava de Itajaí", city: "Itajaí",
                          state: "SC", zip_code: "", provider: "leaflet")
    end

    before { allow(neighborhood_geocoder).to receive(:sleep) }

    it "aceita só bairro/localidade da mesma cidade e marca como aproximado" do
      allow(neighborhood_geocoder).to receive(:json_get) do |_url, params|
        expect(params).to include(featureType: "settlement")
        expect(params[:q]).not_to include("Brasil")
        [
          { "lat" => "-26.9", "lon" => "-48.6", "display_name" => "Praia Brava, Balneário Camboriú", "address" => { "city" => "Balneário Camboriú" } },
          { "lat" => "-26.94", "lon" => "-48.63", "display_name" => "Praia Brava, Itajaí", "address" => { "city" => "Itajaí" } }
        ]
      end

      result = neighborhood_geocoder.neighborhood_call

      expect(result.latitude).to eq("-26.94")
      expect(result.precision).to eq("neighborhood")
    end

    it "sem bairro na mesma cidade, não devolve nada" do
      allow(neighborhood_geocoder).to receive(:json_get)
        .and_return([{ "lat" => "-26.9", "lon" => "-48.6", "address" => { "city" => "Balneário Camboriú" } }])

      expect(neighborhood_geocoder.neighborhood_call).to be_nil
    end
  end
end
