# Páginas públicas consultam a taxa do simulador (Banco Central). Nos testes
# ela vem fixa, sem rede; o spec do próprio serviço usa :real_central_bank_rate.
RSpec.configure do |config|
  config.before do |example|
    next if example.metadata[:real_central_bank_rate]

    allow(Financing::CentralBankRate).to receive(:fetch) do |source = Financing::CentralBankRate::DEFAULT_SOURCE|
      Financing::CentralBankRate::Result.new(annual_rate: 11.3, reference_date: Date.new(2026, 7, 1), source: source.to_s.presence || "bcb_total", fallback: false)
    end
  end
end
