require "rails_helper"

RSpec.describe ErrorEventsCleanupJob, type: :job do
  def create_error_event!(attrs = {})
    now = Time.current
    ErrorEvent.create!(
      {
        fingerprint: SecureRandom.hex(16),
        exception_class: "RuntimeError",
        message: "Falha monitorada",
        backtrace: "app/jobs/example_job.rb:1",
        source: "manual",
        severity: "error",
        occurrences_count: 1,
        first_seen_at: now,
        last_seen_at: now
      }.merge(attrs)
    )
  end

  it "remove resolvidos antigos sem apagar resolvidos recentes ou abertos recentes" do
    resolved_old = create_error_event!(resolved_at: 2.days.ago)
    resolved_recent = create_error_event!(resolved_at: 1.hour.ago)
    unresolved_recent = create_error_event!

    described_class.perform_now

    expect(ErrorEvent.exists?(resolved_old.id)).to eq(false)
    expect(ErrorEvent.exists?(resolved_recent.id)).to eq(true)
    expect(ErrorEvent.exists?(unresolved_recent.id)).to eq(true)
  end

  it "mantém a retenção longa para erro aberto antigo" do
    stale_unresolved = create_error_event!(
      first_seen_at: 91.days.ago,
      last_seen_at: 91.days.ago
    )

    described_class.perform_now

    expect(ErrorEvent.exists?(stale_unresolved.id)).to eq(false)
  end
end
