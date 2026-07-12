class SystemHealthSetting < ApplicationRecord
  PERCENTAGE_FIELDS = %i[
    memory_available_warning_percent memory_available_critical_percent
    disk_warning_percent disk_critical_percent
  ].freeze
  INTEGER_FIELDS = %i[
    swap_warning_mb http_warning_ms http_critical_ms
    application_errors_warning application_errors_critical integration_failures_critical
  ].freeze

  validates(*PERCENTAGE_FIELDS, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 })
  validates(*INTEGER_FIELDS, numericality: { only_integer: true, greater_than_or_equal_to: 0 })
  validate :critical_thresholds_are_consistent

  def self.instance
    first_or_create!
  end

  def thresholds
    {
      memory_available_warning: memory_available_warning_percent.to_f,
      memory_available_critical: memory_available_critical_percent.to_f,
      disk_warning: disk_warning_percent.to_f,
      disk_critical: disk_critical_percent.to_f,
      swap_warning_mb: swap_warning_mb,
      http_warning_ms: http_warning_ms,
      http_critical_ms: http_critical_ms,
      application_errors_warning: application_errors_warning,
      application_errors_critical: application_errors_critical,
      integration_failures_critical: integration_failures_critical
    }
  end

  private

  def critical_thresholds_are_consistent
    errors.add(:memory_available_critical_percent, "deve ser menor ou igual ao limite de atenção") if memory_available_critical_percent.to_f > memory_available_warning_percent.to_f
    errors.add(:disk_critical_percent, "deve ser maior ou igual ao limite de atenção") if disk_critical_percent.to_f < disk_warning_percent.to_f
    errors.add(:http_critical_ms, "deve ser maior ou igual ao limite de atenção") if http_critical_ms.to_i < http_warning_ms.to_i
    errors.add(:application_errors_critical, "deve ser maior ou igual ao limite de atenção") if application_errors_critical.to_i < application_errors_warning.to_i
  end
end
