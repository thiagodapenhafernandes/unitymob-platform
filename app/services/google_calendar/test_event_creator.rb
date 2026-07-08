require "google/apis/calendar_v3"
require "googleauth"
require "stringio"

module GoogleCalendar
  class TestEventCreator
    TIME_ZONE = "America/Sao_Paulo".freeze

    def initialize(setting:, tenant:)
      @setting = setting
      @tenant = tenant
    end

    def call
      raise ArgumentError, "Agenda Google não configurada para esta conta" unless setting.configured?

      calendar_service.insert_event(setting.calendar_id, test_event)
    end

    private

    attr_reader :setting, :tenant

    def calendar_service
      @calendar_service ||= begin
        service = Google::Apis::CalendarV3::CalendarService.new
        service.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
          json_key_io: StringIO.new(setting.service_account_json),
          scope: Google::Apis::CalendarV3::AUTH_CALENDAR
        )
        service
      end
    end

    def test_event
      Google::Apis::CalendarV3::Event.new(
        summary: "Teste integração Unitymob CRM - Agenda fotografia",
        description: "Evento criado pelo teste da integração Google Calendar da conta #{tenant.id}. Pode remover após validar.",
        start: Google::Apis::CalendarV3::EventDateTime.new(
          date_time: start_at.iso8601,
          time_zone: TIME_ZONE
        ),
        end: Google::Apis::CalendarV3::EventDateTime.new(
          date_time: (start_at + 30.minutes).iso8601,
          time_zone: TIME_ZONE
        )
      )
    end

    def start_at
      @start_at ||= 2.days.from_now.in_time_zone(TIME_ZONE).change(min: 0, sec: 0)
    end
  end
end
