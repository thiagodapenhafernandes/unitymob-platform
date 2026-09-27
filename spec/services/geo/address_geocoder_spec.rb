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
end
