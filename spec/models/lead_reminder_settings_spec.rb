require "rails_helper"

RSpec.describe LeadSetting do
  let(:setting) { LeadSetting.instance }

  it "preserva os padrões operacionais atuais" do
    expect(setting.reminder_phases.values.map { |value| value / 60 }).to eq([15, 30, 60])
    expect(setting.reminder_overdue_minutes).to eq(120)
    expect(setting.reminder_retry_minutes).to eq(30)
    expect(setting.reminder_due_enabled).to be(true)
    expect([setting.reminder_start_time, setting.reminder_end_time]).to eq(["08:00", "18:00"])
  end

  it "recusa intervalos inválidos, fases duplicadas e janela invertida" do
    setting.assign_attributes(reminder_first_minutes: 30, reminder_second_minutes: 30,
                              reminder_retry_minutes: 0, reminder_start_time: "18:00", reminder_end_time: "08:00")
    expect(setting).not_to be_valid
    expect(setting.errors[:base]).to be_present
    expect(setting.errors[:reminder_retry_minutes]).to be_present
    expect(setting.errors[:reminder_end_time]).to be_present
    setting.reminder_start_time = "25:00"
    expect(setting).not_to be_valid
    expect(setting.errors[:reminder_start_time]).to be_present
  end
end
