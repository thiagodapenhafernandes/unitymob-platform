require "rails_helper"

RSpec.describe SystemHealthSetting, type: :model do
  it "mantém limites críticos coerentes com os limites de atenção" do
    setting = described_class.new(
      memory_available_warning_percent: 10, memory_available_critical_percent: 20,
      disk_warning_percent: 90, disk_critical_percent: 80,
      http_warning_ms: 2_000, http_critical_ms: 1_000,
      application_errors_warning: 10, application_errors_critical: 5,
      swap_warning_mb: 100, integration_failures_critical: 1
    )

    expect(setting).not_to be_valid
    expect(setting.errors.attribute_names).to include(
      :memory_available_critical_percent, :disk_critical_percent,
      :http_critical_ms, :application_errors_critical
    )
  end
end
