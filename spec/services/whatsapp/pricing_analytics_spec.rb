require "rails_helper"

RSpec.describe Whatsapp::PricingAnalytics do
  let(:sender) { create(:whatsapp_sender_number) }
  let(:starts_on) { Date.current.yesterday }
  let(:ends_on) { starts_on }
  let(:base) { "#{Whatsapp::CloudClient::GRAPH_HOST}/#{Whatsapp::CloudClient.api_version}/#{sender.waba_id}" }
  let(:point) do
    {"start" => starts_on.in_time_zone.beginning_of_day.to_i, "end" => ends_on.next_day.in_time_zone.beginning_of_day.to_i,
     "phone_number" => sender.display_phone_number.gsub(/\D/, ""), "volume" => 7, "cost" => 0.4375,
     "pricing_category" => "MARKETING", "pricing_type" => "REGULAR"}
  end

  def response(payload = nil, code: 200, **fields)
    instance_double(HTTParty::Response, code: code, body: (payload || fields).to_json)
  end

  def fetch(tenant: sender.tenant)
    described_class.call(tenant: tenant, sender: sender, starts_on: starts_on, ends_on: ends_on)
  end

  before do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(HTTParty).to receive(:get).with(base, anything).and_return(response("currency" => "USD"))
    allow(HTTParty).to receive(:get).with("#{base}/pricing_analytics", anything)
      .and_wrap_original { |_method, *_args| response("data" => [{"data_points" => [point]}]) }
  end

  it "usa custo e volume entregues da Meta, na moeda original e sem arredondar antes da exibição" do
    result = fetch
    expect(result.amount).to eq(BigDecimal("0.4375"))
    expect(result.currency).to eq("USD")
    expect(result.delivered).to eq(7)
    expect(result.message).to be_nil
    expect(HTTParty).to have_received(:get).with("#{base}/pricing_analytics", hash_including(
      headers: {"Authorization" => "Bearer #{sender.access_token}"},
      query: hash_including(metric_types: '["COST","VOLUME"]', phone_numbers: [sender.display_phone_number.gsub(/\D/, "")].to_json)))
  end

  it "não cobra envio ou falha usando os parâmetros locais antigos" do
    sender.update!(cpl_sent_unit_price: 999, cpl_fla_unit_price: 999)
    expect(fetch.amount).to eq(BigDecimal("0.4375"))
  end

  it "preserva custo zero confirmado pela Meta" do
    point["cost"] = 0
    expect(fetch.amount).to eq(0)
  end

  it "consulta volume quando a Meta bloqueia custo por cobrança de parceiro, sem inventar preço" do
    error = {"error" => {"code" => 10, "error_subcode" => 2388184, "message" => "texto privado"}}
    allow(HTTParty).to receive(:get).with("#{base}/pricing_analytics", anything)
      .and_return(response(error, code: 400), response("data" => [{"data_points" => [point.except("cost")]}]))
    result = fetch
    expect(result.amount).to be_nil
    expect(result.delivered).to eq(7)
    expect(result.currency).to eq("USD")
    expect(result.message).to include("parceiro")
    expect(result.message).not_to include("texto privado")
  end

  it "não apresenta valor parcial quando algum custo está ausente" do
    point.delete("cost")
    expect(fetch.amount).to be_nil
    expect(fetch.message).to include("custo completo")
  end

  it "não considera falta de dados como gasto zero" do
    allow(HTTParty).to receive(:get).with("#{base}/pricing_analytics", anything).and_return(response("data" => []))
    expect(fetch.amount).to be_nil
    expect(fetch.delivered).to be_nil
  end

  it "recusa dados de outro número ou fora do período" do
    point["phone_number"] = "5511000000000"
    expect(fetch.amount).to be_nil
    expect(fetch.message).to include("fora do número ou período")
  end

  it "recusa relatório paginado incompleto em vez de somar apenas a primeira página" do
    allow(HTTParty).to receive(:get).with("#{base}/pricing_analytics", anything)
      .and_return(response("data" => [{"data_points" => [point]}], "paging" => {"next" => "https://graph.facebook.com/next"}))
    expect(fetch.amount).to be_nil
    expect(fetch.message).to include("parcial")
  end

  it "não presume reais quando a Meta não retorna moeda" do
    allow(HTTParty).to receive(:get).with(base, anything).and_return(response({}))
    expect(fetch.amount).to be_nil
    expect(fetch.message).to include("moeda")
  end

  it "não vaza mensagens do provedor em falhas de autorização" do
    allow(HTTParty).to receive(:get).with(base, anything).and_return(response({"error" => {"message" => "token privado"}}, code: 403))
    expect(fetch.message).not_to include("token privado")
    expect(fetch.amount).to be_nil
  end

  it "trata timeout sem fallback de estimativa" do
    allow(HTTParty).to receive(:get).with(base, anything).and_raise(Net::ReadTimeout)
    expect(fetch.amount).to be_nil
    expect(fetch.message).to include("Tente novamente")
  end

  it "reutiliza o cache por conta, número, credencial e período" do
    2.times { fetch }
    expect(HTTParty).to have_received(:get).with(base, anything).once
    sender.whatsapp_business_integration.update!(access_token: "changed-token")
    fetch
    expect(HTTParty).to have_received(:get).with(base, anything).twice
  end

  it "bloqueia outro tenant antes de consultar a Meta" do
    expect { fetch(tenant: Tenant.create!(name: "Outra", slug: "pricing-other")) }.to raise_error(ArgumentError)
    expect(HTTParty).not_to have_received(:get)
  end

  it "recusa intervalo invertido ou futuro" do
    expect { described_class.call(tenant: sender.tenant, sender: sender, starts_on: Date.tomorrow, ends_on: Date.current) }.to raise_error(ArgumentError)
  end
end
