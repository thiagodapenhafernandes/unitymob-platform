require "rails_helper"

RSpec.describe Meta::ConversionDispatcher do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }
  let(:lead) { create(:lead, tenant: tenant, attribution_channel: "meta_ads") }

  it "enfileira o evento com id estável por lead" do
    MetaConversionConfig.create!(tenant: tenant, dataset_id: "999")
    create(:user_meta_integration, admin_user: admin, tenant: tenant, access_token: "tok")

    expect do
      described_class.call(lead: lead, milestone: :qualified)
    end.to have_enqueued_job(MetaConversionJob).with(
      tenant.id, lead.id, "QualifiedLead",
      described_class.event_id(tenant.id, lead.id, "QualifiedLead"),
      kind_of(String), nil
    )
  end

  it "aceita event_name direto do mapeamento da etapa" do
    MetaConversionConfig.create!(tenant: tenant, dataset_id: "999")
    create(:user_meta_integration, admin_user: admin, tenant: tenant, access_token: "tok")

    expect do
      described_class.call(lead: lead, event_name: "Schedule")
    end.to have_enqueued_job(MetaConversionJob).with(tenant.id, lead.id, "Schedule", kind_of(String), kind_of(String), nil)

    expect do
      described_class.call(lead: lead, event_name: "EventoInventado")
    end.not_to have_enqueued_job(MetaConversionJob)
  end

  it "gera o mesmo event_id para o mesmo lead e evento" do
    expect(described_class.event_id(1, 2, "Purchase")).to eq(described_class.event_id(1, 2, "Purchase"))
    expect(described_class.event_id(1, 2, "Purchase")).not_to eq(described_class.event_id(1, 2, "Schedule"))
  end

  it "ignora lead de outra origem, config ausente/inativa e marco desconhecido" do
    MetaConversionConfig.create!(tenant: tenant, dataset_id: "999", enabled: false)
    create(:user_meta_integration, admin_user: admin, tenant: tenant, access_token: "tok")
    other = create(:lead, tenant: tenant, origin: "site")

    expect do
      described_class.call(lead: other, milestone: :qualified)
      described_class.call(lead: lead, milestone: :qualified)
      described_class.call(lead: lead, milestone: :unknown)
      described_class.call(lead: nil, milestone: :qualified)
    end.not_to have_enqueued_job(MetaConversionJob)
  end
end
