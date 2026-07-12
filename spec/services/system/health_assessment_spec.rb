require "rails_helper"

RSpec.describe System::HealthAssessment do
  let(:healthy_runtime) do
    {
      memory_available_percent: 40, disk_percent: 35, swap_used_mb: 0, http_ms: 120,
      puma: "active", solid_queue: "active", nginx: "active", database: "ok", cache: "ok"
    }
  end

  let(:healthy_platform) do
    {
      release: { migrations_pending: false },
      errors: { application_open: 0, unassigned_open: 0 },
      tenants: []
    }
  end

  it "classifica uma plataforma dentro dos limites como saudável" do
    result = described_class.call(runtime: healthy_runtime, platform: healthy_platform)

    expect(result).to include(status: "healthy", findings: [])
  end

  it "classifica indisponibilidade de serviço e migration pendente como crítica" do
    runtime = healthy_runtime.merge(solid_queue: "inactive")
    platform = healthy_platform.deep_merge(release: { migrations_pending: true })

    result = described_class.call(runtime: runtime, platform: platform)

    expect(result[:status]).to eq("critical")
    expect(result[:findings].pluck(:code)).to include("service_solid_queue", "migrations_pending")
  end

  it "não mistura ruído de tráfego com o limite de erros funcionais" do
    platform = healthy_platform.deep_merge(errors: { application_open: 0, traffic_noise_occurrences: 10_000 })

    expect(described_class.call(runtime: healthy_runtime, platform: platform)[:status]).to eq("healthy")
  end
end
