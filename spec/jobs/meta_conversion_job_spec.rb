require "rails_helper"

RSpec.describe MetaConversionJob, type: :job do
  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }
  let(:lead) { create(:lead, tenant: tenant, attribution_channel: "meta_ads") }
  let(:service) { instance_double(Meta::ConversionService, send_event: :sent) }

  before do
    MetaConversionConfig.create!(tenant: tenant, dataset_id: "999")
    create(:user_meta_integration, admin_user: admin, tenant: tenant, access_token: "tok")
    allow(Meta::ConversionService).to receive(:new).and_return(service)
  end

  it "envia o evento com os argumentos enfileirados" do
    described_class.perform_now(tenant.id, lead.id, "Schedule", "evt-1", Time.current.iso8601, nil)

    expect(service).to have_received(:send_event).with(
      hash_including(lead: lead, event_name: "Schedule", event_id: "evt-1")
    )
  end

  it "não faz nada sem lead, sem origem Meta ou sem config ativa" do
    other = create(:lead, tenant: tenant, origin: "site")

    expect do
      described_class.perform_now(tenant.id, 0, "Schedule", "evt-x", Time.current.iso8601, nil)
      described_class.perform_now(tenant.id, other.id, "Schedule", "evt-x", Time.current.iso8601, nil)
      described_class.perform_now(0, lead.id, "Schedule", "evt-x", Time.current.iso8601, nil)
    end.not_to raise_error
    expect(service).not_to have_received(:send_event)

    MetaConversionConfig.for_tenant(tenant).first.update!(enabled: false)
    described_class.perform_now(tenant.id, lead.id, "Schedule", "evt-x", Time.current.iso8601, nil)
    expect(service).not_to have_received(:send_event)
  end
end
