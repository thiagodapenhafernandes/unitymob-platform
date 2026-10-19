require "rails_helper"

RSpec.describe Ga4::MeasurementClient do
  let(:config) { Ga4ConversionConfig.new(measurement_id: "G-TEST123", api_secret: "test-secret") }
  let(:http) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:new).with("www.google-analytics.com", 443).and_return(http)
    %i[use_ssl= open_timeout= read_timeout= write_timeout= max_retries=].each { |method| allow(http).to receive(method) }
    allow(http).to receive(:start).and_yield(http)
  end

  it "usa HTTPS fixo, sem repetição HTTP automática e sem tratar 204 como ingestão comprovada" do
    allow(http).to receive(:request) do |request|
      expect(request.path).to start_with("/mp/collect?")
      expect(request["Content-Type"]).to eq("application/json")
      expect(JSON.parse(request.body)).to eq("client_id" => "123.456")
      Net::HTTPNoContent.new("1.1", "204", "No Content")
    end
    result = described_class.deliver(config: config, payload: { client_id: "123.456" })
    expect(result.outcome).to eq("http_accepted")
    expect(http).to have_received(:max_retries=).with(0)
  end

  it "sinaliza timeout sem propagar mensagens que possam conter segredos" do
    allow(http).to receive(:request).and_raise(Net::ReadTimeout, "private-token")
    result = described_class.deliver(config: config, payload: {})
    expect(result.outcome).to eq("uncertain")
    expect(result.http_status).to be_nil
  end

  it "mantém erro HTTP como rejeição sem retry cego" do
    allow(http).to receive(:request).and_return(Net::HTTPBadRequest.new("1.1", "400", "Bad Request"))
    expect(described_class.deliver(config: config, payload: {}).outcome).to eq("rejected")
  end
end
