require "rails_helper"

RSpec.describe System::PlatformHealthReport do
  before do
    Rails.cache.clear
    ErrorEvent.delete_all
  end

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

  it "cacheia o cálculo pesado de armazenamento por tenant" do
    tenant = Tenant.create!(name: "Conta storage", slug: "conta-storage-#{SecureRandom.hex(3)}", active: true)
    tenant.habitations.create!(codigo: "STORAGE-#{SecureRandom.hex(3)}", categoria: "Apartamento")

    described_class.call

    sql = []
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      sql << payload[:sql].to_s if payload[:sql].to_s.include?("active_storage_blobs.byte_size")
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      described_class.call
    end

    expect(sql).to be_empty
  end
end
