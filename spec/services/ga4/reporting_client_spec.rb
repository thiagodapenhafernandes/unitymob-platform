require "rails_helper"

RSpec.describe Ga4::ReportingClient do
  let(:config) { Ga4ConversionConfig.new(reporting_property_id: "123456", reporting_credentials: { type: "service_account", client_email: "reader@project.iam.gserviceaccount.com", private_key: "fake" }.to_json) }
  let(:http) { instance_double(Net::HTTP) }
  let(:auth) { double(fetch_access_token!: { "access_token" => "private-token" }) }
  before do
    allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(auth)
    allow(Net::HTTP).to receive(:new).with("analyticsdata.googleapis.com", 443).and_return(http)
    %i[use_ssl= open_timeout= read_timeout= write_timeout= max_retries=].each { |method| allow(http).to receive(method) }
    allow(http).to receive(:start).and_yield(http)
  end
  def read_report
    described_class.call(config: config, start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 18))
  end

  it "consulta somente eventos agregados na propriedade e distingue resposta vazia de falha" do
    allow(http).to receive(:request) do |request|
      expect(request.path).to eq("/v1beta/properties/123456:runReport")
      expect(request["Authorization"]).to eq("Bearer private-token")
      body = JSON.parse(request.body)
      expect(body["dimensions"]).to eq([{ "name" => "eventName" }])
      expect(body["dateRanges"]).to eq([{ "startDate" => "2026-10-01", "endDate" => "2026-10-18" }])
      expect(body.dig("dimensionFilter", "filter", "inListFilter", "values")).to eq(described_class::EVENTS)
      double(code: "200", body: { dimensionHeaders: [{ name: "eventName" }], metricHeaders: [{ name: "eventCount" }], metadata: { timeZone: "America/Sao_Paulo" }, rows: [] }.to_json)
    end
    expect(read_report).to include(status: :ok, counts: described_class::EVENTS.index_with { 0 })
    allow(http).to receive(:request).and_return(double(code: "403", body: "private error"))
    expect { read_report }.to raise_error(IOError, "GA4 reporting unavailable")
  end

  it "preserva alerta de limiares e rejeita contagens inválidas" do
    body = { dimensionHeaders: [{ name: "eventName" }], metricHeaders: [{ name: "eventCount" }], rows: [{ dimensionValues: [{ value: "qualify_lead" }], metricValues: [{ value: "2" }] }], metadata: { subjectToThresholding: true } }
    allow(http).to receive(:request).and_return(double(code: "200", body: body.to_json))
    expect(read_report).to include(counts: described_class::EVENTS.index_with { |name| name == "qualify_lead" ? 2 : 0 }, limited: true)
    body[:rows][0][:metricValues][0][:value] = "unknown"
    allow(http).to receive(:request).and_return(double(code: "200", body: body.to_json))
    expect { read_report }.to raise_error(TypeError)
  end
end
