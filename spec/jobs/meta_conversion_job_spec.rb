require "rails_helper"

RSpec.describe MetaConversionJob, type: :job do
  include ActiveJob::TestHelper
  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }
  let(:lead) { create(:lead, tenant: tenant, attribution_channel: "meta_ads") }
  let(:service) { instance_double(Meta::ConversionService, send_event: :sent) }

  before do
    MetaConversionConfig.create!(tenant: tenant, datasets: [{ "id" => "999" }])
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

  it "não envia se a conexão expirar enquanto o evento aguarda na fila" do
    UserMetaIntegration.owned_by_tenant(tenant.id).update_all(token_expires_at: 1.second.ago)

    described_class.perform_now(tenant.id, lead.id, "Schedule", "evt-expired", Time.current.iso8601, nil)

    expect(service).not_to have_received(:send_event)
  end

  it "não acessa lead de outro tenant" do
    other = Tenant.create!(name: "Outro tenant", slug: "outro-#{SecureRandom.hex(3)}")
    foreign_lead = create(:lead, tenant: other, attribution_channel: "meta_ads")

    described_class.perform_now(tenant.id, foreign_lead.id, "Schedule", "evt-foreign", Time.current.iso8601, nil)

    expect(service).not_to have_received(:send_event)
  end

  it "agenda retry com o mesmo evento quando o recebimento não é confirmado" do
    allow(service).to receive(:send_event).and_raise(Meta::ConversionService::ConversionError, "recebimento não confirmado")
    args = [tenant.id, lead.id, "Schedule", "evt-retry", Time.current.iso8601, nil]
    original = lead.attributes.deep_dup

    expect { described_class.perform_now(*args) }.to have_enqueued_job(described_class).with(*args)
    expect(lead.reload.attributes).to eq(original)
  end
end
