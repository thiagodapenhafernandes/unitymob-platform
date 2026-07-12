require "rails_helper"

RSpec.describe System::PlatformHealthReport do
  it "separa erros funcionais de ruído e agrega saúde por tenant" do
    tenant = Tenant.create!(name: "Conta saúde", slug: "conta-saude-#{SecureRandom.hex(3)}", active: true)
    tenant.habitations.create!(codigo: "HEALTH-#{SecureRandom.hex(3)}", categoria: "Apartamento")
    ErrorEvent.create!(fingerprint: SecureRandom.hex(32), exception_class: "RuntimeError", message: "falha", source: "request", severity: "error", tenant_id: tenant.id, occurrences_count: 2, first_seen_at: Time.current, last_seen_at: Time.current)
    ErrorEvent.create!(fingerprint: SecureRandom.hex(32), exception_class: "ActionController::RoutingError", message: "rota", source: "request", severity: "warning", occurrences_count: 10, first_seen_at: Time.current, last_seen_at: Time.current)

    report = described_class.call
    row = report[:tenants].find { |item| item[:id] == tenant.id }

    expect(row).to include(status: "attention", habitations: 1, open_errors: 1)
    expect(report[:errors]).to include(application_open: 1, traffic_noise_open: 1, traffic_noise_occurrences: 10, affected_tenants: 1)
  end
end
