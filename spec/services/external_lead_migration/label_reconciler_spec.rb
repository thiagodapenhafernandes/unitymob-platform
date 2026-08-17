require "rails_helper"

RSpec.describe ExternalLeadMigration::LabelReconciler do
  let(:tenant) { Tenant.default }
  let(:broker) { create(:admin_user, tenant:, email: "broker-c2s-labels@example.test") }

  before { Current.tenant = tenant }

  it "faz dry-run de etiquetas C2S sem alterar o banco" do
    create_c2s_lead(name: "Lead com etiqueta", tags: [{ "tag_name" => "Instagram Leads" }, { "tag_name" => "VIP" }])

    result = described_class.call(tenant: tenant, execute: false)

    expect(result).to have_attributes(scanned: 1, labels_created: 2, labelings_created: 2, skipped: 0)
    expect(broker.lead_labels).to be_empty
  end

  it "cria etiquetas nativas e vincula aos leads historicos do C2S" do
    lead = create_c2s_lead(name: "Lead historico", tags: [{ "tag_name" => "Instagram Leads" }, { "tag_name" => "VIP" }])

    result = described_class.call(tenant: tenant, execute: true)

    expect(result).to have_attributes(scanned: 1, labels_created: 2, labelings_created: 2, skipped: 0)
    expect(lead.reload.lead_labels.pluck(:name)).to contain_exactly("Instagram Leads", "VIP")
    expect(broker.lead_labels.pluck(:color).uniq).to eq(["gray"])
  end

  def create_c2s_lead(name:, tags:)
    create(
      :lead,
      tenant: tenant,
      admin_user: broker,
      name: name,
      origin: ExternalLeadIntegration::LEAD_ORIGIN,
      other_information: {
        "source" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY,
        "external_lead_payload" => {
          "attributes" => {
            "tags" => tags
          }
        }
      }
    )
  end
end
