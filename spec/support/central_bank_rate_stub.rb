# Páginas públicas consultam a taxa do simulador (Banco Central). Nos testes
# ela vem fixa, sem rede; o spec do próprio serviço usa :real_central_bank_rate.
RSpec.configure do |config|
  config.before do |example|
    next if example.metadata[:real_central_bank_rate]

    rates = { "bcb_total" => 11.3, "bcb_regulated" => 10.92, "bcb_market" => 14.28 }
    allow(Financing::CentralBankRate).to receive(:fetch) do |source = Financing::CentralBankRate::DEFAULT_SOURCE|
      key = rates.key?(source.to_s) ? source.to_s : "bcb_total"
      Financing::CentralBankRate::Result.new(annual_rate: rates[key], reference_date: Date.new(2026, 7, 1), source: key, fallback: false)
    end
  end
end
