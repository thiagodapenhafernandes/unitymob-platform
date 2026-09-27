require "rails_helper"

RSpec.describe Financing::CentralBankRate, :real_central_bank_rate do
  def http_response(body, success: true)
    klass = success ? Net::HTTPOK : Net::HTTPServiceUnavailable
    instance_double(klass, body: body).tap { |response| allow(response).to receive(:is_a?) { |k| k == Net::HTTPSuccess ? success : false } }
  end

  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original
  end

  it "lê a última taxa da série do Banco Central com o mês de referência" do
    allow(Net::HTTP).to receive(:start).and_return(http_response('[{"data":"01/07/2026","valor":"11.30"}]'))

    result = described_class.fetch("bcb_total")

    expect(result.annual_rate).to eq(11.3)
    expect(result.reference_date).to eq(Date.new(2026, 7, 1))
    expect(result.fallback).to be(false)
  end

  it "usa a série da fonte escolhida e cai no padrão para fonte desconhecida" do
    allow(Net::HTTP).to receive(:start).and_return(http_response('[{"data":"01/07/2026","valor":"10.92"}]'))

    described_class.fetch("bcb_regulated")
    expect(Net::HTTP).to have_received(:start).once
    expect(described_class.fetch("qualquer").source).to eq("bcb_total")
  end

  it "se a API falhar, usa o último valor bom e, sem ele, a taxa de reserva" do
    allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout)
    expect(described_class.fetch("bcb_market")).to have_attributes(annual_rate: 8.5, fallback: true)

    Rails.cache.clear
    Rails.cache.write(described_class.last_good_key("bcb_market"), { annual_rate: 14.28, reference_date: Date.new(2026, 7, 1), source: "bcb_market", fallback: false })
    expect(described_class.fetch("bcb_market").annual_rate).to eq(14.28)
  end

  it "ignora resposta sem número válido" do
    allow(Net::HTTP).to receive(:start).and_return(http_response('[{"data":"01/07/2026","valor":"abc"}]'))

    expect(described_class.fetch("bcb_total").fallback).to be(true)
  end
end
