class AppointmentMailer < ApplicationMailer
  def invite
    @appointment = params[:appointment]
    @lead = @appointment.lead
    @site_name = LayoutSetting.instance(tenant: appointment_tenant).site_name.presence || appointment_tenant.name

    attachments["convite.ics"] = { mime_type: "text/calendar", content: build_ics }

    mail(
      to: params[:recipients],
      subject: "Convite: Visita agendada - #{@site_name}"
    )
  end

  private

  def appointment_tenant
    @appointment.tenant
  end

  def build_ics
    starts_at = @appointment.starts_at.utc.strftime("%Y%m%dT%H%M%SZ")
    ends_at = (@appointment.ends_at || @appointment.starts_at + 1.hour).utc.strftime("%Y%m%dT%H%M%SZ")
    stamp = Time.current.utc.strftime("%Y%m%dT%H%M%SZ")
    description = [@appointment.notes, @appointment.location].compact_blank.join(" — ").gsub("\n", "\\n")

    <<~ICS.gsub("\n", "\r\n")
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//#{@site_name}//Agenda//PT
      CALSCALE:GREGORIAN
      METHOD:PUBLISH
      BEGIN:VEVENT
      UID:appointment-#{@appointment.id}@#{appointment_tenant.id}
      DTSTAMP:#{stamp}
      DTSTART:#{starts_at}
      DTEND:#{ends_at}
      SUMMARY:#{@appointment.title}
      DESCRIPTION:#{description}
      LOCATION:#{@appointment.location}
      END:VEVENT
      END:VCALENDAR
    ICS
  end
end
