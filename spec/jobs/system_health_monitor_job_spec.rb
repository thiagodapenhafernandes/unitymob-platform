require "rails_helper"

RSpec.describe SystemHealthMonitorJob, type: :job do
  let!(:tenant) { Tenant.create!(name: "Tenant monitorado", slug: "tenant-monitorado-#{SecureRandom.hex(3)}", active: true) }
  let(:runtime) do
    {
      status: "healthy", collected_at: Time.current.iso8601, memory_available_percent: 30,
      disk_percent: 40, swap_used_mb: 0, http_ms: 100, puma: "active",
      solid_queue: "active", nginx: "active", database: "ok", cache: "ok"
    }
  end
  let(:platform) do
    {
      release: { migrations_pending: false },
      errors: { application_open: 0, unassigned_open: 0 },
      tenants: [{ id: tenant.id, name: tenant.name, slug: tenant.slug, status: "healthy", integration_failures: 0, open_errors: 0 }]
    }
  end

  before do
    allow(System::HealthSnapshot).to receive(:call).and_return(runtime)
    allow(System::PlatformHealthReport).to receive(:call).and_return(platform)
  end

  it "persiste amostras global e por tenant" do
    expect { described_class.perform_now }.to change(SystemHealthSnapshot, :count).by(2)

    expect(SystemHealthSnapshot.platform.last.status).to eq("healthy")
    expect(SystemHealthSnapshot.where(tenant: tenant).last.status).to eq("healthy")
  end

  it "remove amostras vencidas" do
    SystemHealthSnapshot.create!(status: "healthy", source: "platform", collected_at: 91.days.ago)

    described_class.perform_now

    expect(SystemHealthSnapshot.where("collected_at < ?", 90.days.ago)).to be_empty
  end

  it "notifica pelos canais operacionais quando a plataforma está crítica" do
    allow(System::HealthAssessment).to receive(:call).and_return(
      status: "critical", findings: [{ code: "database", severity: "critical", message: "Banco indisponível" }]
    )
    allow(Rails.cache).to receive(:write).and_return(true)
    allow(Notifications::PushDispatcher).to receive(:deliver)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SYSTEM_HEALTH_ALERT_EMAIL").and_return("operacao@example.com")

    expect { described_class.perform_now }.to have_enqueued_mail(SystemHealthAlertMailer, :degraded)
  end
end
