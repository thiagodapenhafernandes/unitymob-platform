require "rails_helper"

RSpec.describe GoogleCalendar::PhotoEventSyncer do
  let(:tenant) { Tenant.default }
  let(:habitation) do
    create(
      :habitation,
      :broker_intake,
      tenant: tenant,
      codigo: "CAP-123",
      titulo_anuncio: "Apartamento Teste",
      photo_session_requested_at: Time.zone.parse("2026-07-10 10:00")
    )
  end
  let(:setting) do
    GoogleCalendarIntegrationSetting.for(tenant).tap do |record|
      record.update!(
        enabled: true,
        calendar_id: "fotografias.saluteimoveis@gmail.com",
        default_duration_minutes: 60,
        service_account_json: {
          type: "service_account",
          client_email: "calendar-sync@salute-crm-501321.iam.gserviceaccount.com",
          private_key: "-----BEGIN PRIVATE KEY-----\nFAKE\n-----END PRIVATE KEY-----\n"
        }.to_json
      )
    end
  end

  it "insere evento e grava o id no imovel" do
    service = instance_double(Google::Apis::CalendarV3::CalendarService)
    event_response = Google::Apis::CalendarV3::Event.new(id: "evt_123")
    syncer = described_class.new(habitation: habitation, tenant: tenant, setting: setting)

    allow(syncer).to receive(:calendar_service).and_return(service)
    expect(service).to receive(:insert_event) do |calendar_id, event|
      expect(calendar_id).to eq("fotografias.saluteimoveis@gmail.com")
      expect(event.summary).to include("CAP-123")
      expect(event.start.time_zone).to eq("America/Sao_Paulo")
      expect(event.end.date_time).to eq("2026-07-10T11:00:00-03:00")
      event_response
    end

    syncer.call

    habitation.reload
    expect(habitation.photo_calendar_provider).to eq("google_calendar")
    expect(habitation.photo_calendar_event_id).to eq("evt_123")
    expect(habitation.photo_calendar_error).to be_nil
    expect(habitation.photo_calendar_synced_at).to be_present
  end

  it "atualiza evento existente sem duplicar" do
    habitation.update!(photo_calendar_event_id: "evt_existing")
    service = instance_double(Google::Apis::CalendarV3::CalendarService)
    event_response = Google::Apis::CalendarV3::Event.new(id: "evt_existing")
    syncer = described_class.new(habitation: habitation, tenant: tenant, setting: setting)

    allow(syncer).to receive(:calendar_service).and_return(service)
    expect(service).to receive(:update_event).with("fotografias.saluteimoveis@gmail.com", "evt_existing", instance_of(Google::Apis::CalendarV3::Event)).and_return(event_response)

    syncer.call

    expect(habitation.reload.photo_calendar_event_id).to eq("evt_existing")
  end

  it "sincroniza automaticamente o agendamento interno com o Google" do
    habitation.update!(photo_flow_choice: "schedule")
    service = instance_double(Google::Apis::CalendarV3::CalendarService)
    event_response = Google::Apis::CalendarV3::Event.new(id: "evt_google")
    syncer = described_class.new(habitation: habitation, tenant: tenant, setting: setting)

    allow(syncer).to receive(:calendar_service).and_return(service)
    expect(service).to receive(:insert_event).with(
      "fotografias.saluteimoveis@gmail.com",
      instance_of(Google::Apis::CalendarV3::Event)
    ).and_return(event_response)

    syncer.call

    expect(habitation.reload.photo_calendar_event_id).to eq("evt_google")
  end

  it "remove do Google quando a captacao deixa de ser um agendamento" do
    habitation.update!(
      photo_flow_choice: "upload",
      photo_calendar_provider: "google_calendar",
      photo_calendar_event_id: "evt_existing"
    )
    service = instance_double(Google::Apis::CalendarV3::CalendarService)
    syncer = described_class.new(habitation: habitation, tenant: tenant, setting: setting)

    allow(syncer).to receive(:calendar_service).and_return(service)
    expect(service).to receive(:delete_event).with("fotografias.saluteimoveis@gmail.com", "evt_existing")

    syncer.call

    habitation.reload
    expect(habitation.photo_calendar_event_id).to be_nil
    expect(habitation.photo_calendar_provider).to be_nil
    expect(habitation.photo_calendar_error).to be_nil
  end
end
