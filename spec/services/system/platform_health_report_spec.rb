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
    ErrorEvent.create!(fingerprint: SecureRandom.hex(32), exception_class: "Storage::CriticalBlobIntegrityJob::CriticalBlobCheckFailed", message: "falha ao verificar blob", source: "job", severity: "warning", tenant_id: tenant.id, occurrences_count: 3, first_seen_at: Time.current, last_seen_at: Time.current, context: { report_source: "storage.critical_blob_integrity" })
    ErrorEvent.create!(fingerprint: SecureRandom.hex(32), exception_class: "ActionController::RoutingError", message: "rota", source: "request", severity: "warning", occurrences_count: 10, first_seen_at: Time.current, last_seen_at: Time.current)

    report = described_class.call
    row = report[:tenants].find { |item| item[:id] == tenant.id }

    expect(row).to include(status: "attention", habitations: 1, open_errors: 2)
    expect(report[:errors]).to include(application_open: 2, application_error_open: 1, application_warning_open: 1, traffic_noise_open: 1, traffic_noise_occurrences: 10, affected_tenants: 1)
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

  it "separa erros abertos antigos de ocorrências recentes" do
    ErrorEvent.create!(
      fingerprint: SecureRandom.hex(16),
      exception_class: "RuntimeError",
      message: "Falha antiga",
      backtrace: "app/jobs/example_job.rb:1",
      source: "manual",
      severity: "error",
      occurrences_count: 1,
      first_seen_at: 2.hours.ago,
      last_seen_at: 2.hours.ago
    )
    ErrorEvent.create!(
      fingerprint: SecureRandom.hex(16),
      exception_class: "RuntimeError",
      message: "Falha recente",
      backtrace: "app/jobs/example_job.rb:2",
      source: "manual",
      severity: "error",
      occurrences_count: 1,
      first_seen_at: 5.minutes.ago,
      last_seen_at: 5.minutes.ago
    )

    errors = described_class.call.fetch(:errors)

    expect(errors).to include(
      application_open: 2,
      application_error_open: 2,
      recent_application_open: 1,
      recent_application_error_open: 1
    )
  end
end
