require "rails_helper"

RSpec.describe System::HealthSnapshot do
  it "usa o caminho configurado quando SYSTEM_HEALTH_SNAPSHOT_PATH está definido" do
    file = Tempfile.new("system-health")
    file.write({ status: "healthy", collected_at: Time.current.iso8601 }.to_json)
    file.close

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SYSTEM_HEALTH_SNAPSHOT_PATH").and_return(file.path)

    expect(described_class.call).to include(status: "healthy")
  ensure
    file&.unlink
  end

  it "não depende do caminho fixo da Salute quando não há configuração explícita" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SYSTEM_HEALTH_SNAPSHOT_PATH").and_return(nil)

    snapshot = described_class.new
    path = snapshot.send(:default_snapshot_path).to_s

    expect(path).to end_with("/tmp/system_health.json")
    expect(path).not_to include("/home/salute/deploy/shared")
  end

  it "calcula snapshot básico quando o arquivo externo não existe" do
    snapshot = described_class.new
    allow(snapshot).to receive(:snapshot_path).and_return(Rails.root.join("tmp", "missing-system-health.json"))
    allow(snapshot).to receive(:healthz_result).and_return(status: "ok", http_status: 200, http_ms: 42)
    allow(snapshot).to receive(:database_state).and_return("ok")
    allow(snapshot).to receive(:cache_state).and_return("ok")
    allow(snapshot).to receive(:queue_state).and_return("ok")
    allow(snapshot).to receive(:memory_available_percent).and_return(50)
    allow(snapshot).to receive(:swap_used_mb).and_return(0)
    allow(snapshot).to receive(:disk_percent).and_return(20)
    allow(snapshot).to receive(:load_average).and_return([0.1, 0.2])

    expect(snapshot.call).to include(
      status: "healthy",
      http_status: 200,
      puma: "active",
      solid_queue: "active",
      nginx: "active",
      database: "ok",
      cache: "ok"
    )
  end
end
