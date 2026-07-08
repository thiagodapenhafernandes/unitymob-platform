require "google/apis/calendar_v3"
require "googleauth"
require "stringio"

module GoogleCalendar
  class AvailabilityReader
    TIME_ZONE = "America/Sao_Paulo".freeze
    SLOT_TIMES = %w[09:00 09:45 10:30 11:15 14:00 14:45 15:30 16:15].freeze

    def initialize(setting:, tenant:, start_date:, days: 30, duration_minutes: nil)
      @setting = setting
      @tenant = tenant
      @start_date = start_date.to_date
      @days = days.to_i
      @duration_minutes = duration_minutes.presence || setting.default_duration_minutes
    end

    def busy_slot_values
      busy_periods.flat_map do |period|
        slot_values_for_period(period)
      end.uniq.sort
    end

    def busy_at?(time)
      slot_start = time.in_time_zone(TIME_ZONE)
      slot_end = slot_start + duration_minutes.minutes

      busy_periods.any? do |period|
        overlaps?(slot_start, slot_end, period.fetch(:start), period.fetch(:end))
      end
    end

    private

    attr_reader :setting, :tenant, :start_date, :days, :duration_minutes

    def busy_periods
      @busy_periods ||= begin
        return [] unless setting&.configured?

        response = calendar_service.query_freebusy(freebusy_request)
        calendar = response.calendars[setting.calendar_id]
        Array(calendar&.busy).filter_map do |period|
          start_time = parse_google_time(period.start)
          end_time = parse_google_time(period.end)
          next if start_time.blank? || end_time.blank?

          { start: start_time, end: end_time }
        end
      end
    end

    def freebusy_request
      Google::Apis::CalendarV3::FreeBusyRequest.new(
        time_min: start_date.in_time_zone(TIME_ZONE).beginning_of_day.iso8601,
        time_max: (start_date + days).in_time_zone(TIME_ZONE).end_of_day.iso8601,
        time_zone: TIME_ZONE,
        items: [
          Google::Apis::CalendarV3::FreeBusyRequestItem.new(id: setting.calendar_id)
        ]
      )
    end

    def calendar_service
      @calendar_service ||= begin
        service = Google::Apis::CalendarV3::CalendarService.new
        service.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
          json_key_io: StringIO.new(setting.service_account_json),
          scope: Google::Apis::CalendarV3::AUTH_CALENDAR_READONLY
        )
        service
      end
    end

    def slot_values_for_period(period)
      date_range.flat_map do |date|
        SLOT_TIMES.filter_map do |slot|
          slot_start = Time.zone.parse("#{date.iso8601} #{slot}").in_time_zone(TIME_ZONE)
          slot_end = slot_start + duration_minutes.minutes
          next unless overlaps?(slot_start, slot_end, period.fetch(:start), period.fetch(:end))

          slot_start.strftime("%Y-%m-%dT%H:%M")
        end
      end
    end

    def date_range
      start_date...(start_date + days)
    end

    def overlaps?(slot_start, slot_end, busy_start, busy_end)
      slot_start < busy_end && slot_end > busy_start
    end

    def parse_google_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s).in_time_zone(TIME_ZONE)
    end
  end
end
