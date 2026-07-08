require "rails_helper"
require "ostruct"

RSpec.describe GoogleCalendar::AvailabilityReader do
  let(:tenant) { Tenant.default }
  let(:calendar_id) { "fotografias.saluteimoveis@gmail.com" }
  let(:setting) do
    GoogleCalendarIntegrationSetting.for(tenant).tap do |record|
      record.update!(
        enabled: true,
        calendar_id: calendar_id,
        default_duration_minutes: 60,
        service_account_json: {
          type: "service_account",
          client_email: "calendar-sync@example.com",
          private_key: "-----BEGIN PRIVATE KEY-----\nFAKE\n-----END PRIVATE KEY-----\n"
        }.to_json
      )
    end
  end

  it "converte períodos ocupados do Google Calendar em slots bloqueados" do
    service = instance_double(Google::Apis::CalendarV3::CalendarService)
    response = OpenStruct.new(
      calendars: {
        calendar_id => OpenStruct.new(
          busy: [
            OpenStruct.new(
              start: "2026-07-10T10:00:00-03:00",
              end: "2026-07-10T11:00:00-03:00"
            )
          ]
        )
      }
    )
    reader = described_class.new(setting: setting, tenant: tenant, start_date: Date.new(2026, 7, 10), days: 1)

    allow(reader).to receive(:calendar_service).and_return(service)
    expect(service).to receive(:query_freebusy).and_return(response)

    expect(reader.busy_slot_values).to include("2026-07-10T09:45", "2026-07-10T10:30")
    expect(reader.busy_slot_values).not_to include("2026-07-10T09:00")
  end

  it "identifica conflito para um horário específico" do
    service = instance_double(Google::Apis::CalendarV3::CalendarService)
    response = OpenStruct.new(
      calendars: {
        calendar_id => OpenStruct.new(
          busy: [
            OpenStruct.new(
              start: "2026-07-10T14:00:00-03:00",
              end: "2026-07-10T15:00:00-03:00"
            )
          ]
        )
      }
    )
    reader = described_class.new(setting: setting, tenant: tenant, start_date: Date.new(2026, 7, 10), days: 1)

    allow(reader).to receive(:calendar_service).and_return(service)
    allow(service).to receive(:query_freebusy).and_return(response)

    expect(reader.busy_at?(Time.zone.parse("2026-07-10 14:45"))).to eq(true)
    expect(reader.busy_at?(Time.zone.parse("2026-07-10 16:15"))).to eq(false)
  end
end
