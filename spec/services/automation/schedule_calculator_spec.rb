require "rails_helper"

RSpec.describe Automation::ScheduleCalculator do
  it "pula sábado e domingo antes da abertura comercial" do
    now = Time.zone.parse("2026-10-17 08:00")
    result = described_class.wait_until({ mode: "next_business_window", skip_weekends: true }, now: now)
    expect(result).to eq(Time.zone.parse("2026-10-19 09:00"))
  end

  it "permite sábado quando fins de semana estão habilitados" do
    now = Time.zone.parse("2026-10-17 08:00")
    expect(described_class.wait_until({ mode: "next_business_window", skip_weekends: false }, now: now)).to eq(Time.zone.parse("2026-10-17 09:00"))
  end
  it "rejeita janelas inválidas na definição e no runtime" do
    ["09:00", "08:00", "25:00"].each do |finish|
      config = { mode: "business_duration", amount: 1, unit: "hours", business_start: "09:00", business_end: finish }
      expect(described_class.validation_messages(config)).not_to be_empty
      expect { described_class.wait_until(config) }.to raise_error(ArgumentError)
      definition = Automation::WorkflowDefinition.default_definition
      definition["nodes"] << { "id" => "wait_1", "type" => "wait", "config" => config }
      expect(Automation::WorkflowDefinition.validate(definition).join).to include("janela comercial")
    end
  end

  it "valida frequência, horário e dia sem truncar configurações inválidas" do
    expect(described_class.recurring_validation_messages({ interval: "1" })).to be_empty
    ["0", "1.5", "abc"].each do |interval|
      expect(described_class.recurring_validation_messages({ interval: interval })).not_to be_empty
    end
    expect(described_class.recurring_validation_messages({ schedule_frequency: "daily", time_of_day: "25:00" })).not_to be_empty
    expect(described_class.recurring_validation_messages({ schedule_frequency: "monthly", month_day: "32" })).not_to be_empty
    expect(described_class.recurring_validation_messages({ schedule_frequency: "weekly", weekdays: ["7"] })).not_to be_empty
  end

  it "observa intervalos de um minuto e a janela de dois minutos da rotina diária" do
    now = Time.zone.parse("2026-10-13 09:01")
    expect(described_class.recurring_bucket({ interval: 1 }, now: now)).not_to eq(described_class.recurring_bucket({ interval: 1 }, now: now + 1.minute))
    expect(described_class.recurring_due?({ schedule_frequency: "daily", time_of_day: "09:00" }, now: now)).to be true
    expect(described_class.recurring_due?({ schedule_frequency: "daily", time_of_day: "09:00" }, now: now + 2.minutes)).to be false
  end

end
