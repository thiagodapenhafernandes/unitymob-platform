require "google/apis/calendar_v3"
require "googleauth"
require "stringio"

module GoogleCalendar
  class PhotoEventSyncer
    TIME_ZONE = "America/Sao_Paulo".freeze
    PROVIDER = "google_calendar".freeze

    def initialize(habitation:, tenant: nil, setting: nil)
      @habitation = habitation
      @tenant = tenant || habitation&.tenant || Current.tenant
      @setting = setting || GoogleCalendarIntegrationSetting.for(@tenant)
    end

    def call
      return skipped unless syncable?

      event = build_event
      response =
        if habitation.photo_calendar_event_id.present?
          calendar_service.update_event(setting.calendar_id, habitation.photo_calendar_event_id, event)
        else
          calendar_service.insert_event(setting.calendar_id, event)
        end

      habitation.update_columns(
        photo_calendar_provider: PROVIDER,
        photo_calendar_event_id: response.id,
        photo_calendar_error: nil,
        photo_calendar_synced_at: Time.current,
        updated_at: Time.current
      )
      setting.update_columns(last_synced_at: Time.current, updated_at: Time.current) if setting.persisted?
      response
    rescue StandardError => error
      record_error(error)
      raise
    end

    private

    attr_reader :habitation, :tenant, :setting

    def syncable?
      tenant.present? &&
        setting.configured? &&
        habitation.photo_flow_choice.in?(%w[schedule google_calendar]) &&
        habitation.photo_session_requested_at.present?
    end

    def skipped
      nil
    end

    def calendar_service
      @calendar_service ||= begin
        service = Google::Apis::CalendarV3::CalendarService.new
        service.authorization = credentials
        service
      end
    end

    def credentials
      Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(setting.service_account_json),
        scope: Google::Apis::CalendarV3::AUTH_CALENDAR
      )
    end

    def build_event
      Google::Apis::CalendarV3::Event.new(
        summary: event_summary,
        description: event_description,
        start: Google::Apis::CalendarV3::EventDateTime.new(
          date_time: start_time.iso8601,
          time_zone: TIME_ZONE
        ),
        end: Google::Apis::CalendarV3::EventDateTime.new(
          date_time: end_time.iso8601,
          time_zone: TIME_ZONE
        )
      )
    end

    def start_time
      @start_time ||= habitation.photo_session_requested_at.in_time_zone(TIME_ZONE)
    end

    def end_time
      start_time + setting.default_duration_minutes.to_i.minutes
    end

    def event_summary
      code = habitation.codigo.presence || "sem código"
      title = habitation.titulo_anuncio.presence || habitation.nome_empreendimento.presence || habitation.categoria.presence || "Imóvel"
      "Fotografia - #{code} - #{title}"
    end

    def event_description
      [
        "Captação de imóvel para fotografia.",
        "Código CRM: #{habitation.codigo.presence || '-'}",
        "Proprietário: #{habitation.proprietario.presence || '-'}",
        "Telefone proprietário: #{habitation.proprietario_celular.presence || '-'}",
        "Endereço: #{address_line}",
        "Captador: #{habitation.admin_user&.name.presence || '-'}"
      ].join("\n")
    end

    def address_line
      [
        habitation.logradouro,
        habitation.numero,
        habitation.complemento,
        habitation.bairro,
        habitation.cidade,
        habitation.uf
      ].compact_blank.join(", ").presence || "-"
    end

    def record_error(error)
      return unless habitation&.persisted?

      habitation.update_columns(
        photo_calendar_provider: PROVIDER,
        photo_calendar_error: error.message.to_s.truncate(500),
        updated_at: Time.current
      )
    rescue StandardError
      nil
    end
  end
end
