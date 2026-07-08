require "rails_helper"

RSpec.describe Lead, type: :model do
  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = Tenant.default
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  describe "tenant consistency" do
    it "rejects responsible users and distribution rules from another tenant" do
      tenant = Tenant.create!(name: "Lead tenant #{SecureRandom.hex(3)}", slug: "lead-tenant-#{SecureRandom.hex(3)}")
      other_tenant = Tenant.create!(name: "Other lead tenant #{SecureRandom.hex(3)}", slug: "other-lead-tenant-#{SecureRandom.hex(3)}")
      profile = other_tenant.profiles.find_by!(key: "agent")
      other_user = create(:admin_user, tenant: other_tenant, profile: profile, email: "lead-other-#{SecureRandom.hex(6)}@salute.test")
      other_rule = create(:distribution_rule, tenant: other_tenant, name: "Regra externa")

      lead = build(:lead, tenant: tenant, admin_user: other_user, shared_by_admin_user: other_user, distribution_rule: other_rule)

      expect(lead).not_to be_valid
      expect(lead.errors[:admin_user]).to include("deve pertencer ao mesmo Tenant")
      expect(lead.errors[:shared_by_admin_user]).to include("deve pertencer ao mesmo Tenant")
      expect(lead.errors[:distribution_rule]).to include("deve pertencer ao mesmo Tenant")
    end
  end

  describe ".origin_options" do
    it "combina catalogo manual com origens ja gravadas nos leads" do
      AttributeOption.create!(context: "lead", category: "source", name: "Instagram")
      create(:lead, origin: "Site")
      create(:lead, origin: "Google Ads")
      create(:lead, origin: "Site")

      expect(described_class.origin_options).to eq(["Google Ads", "Instagram", "Site"])
    end

    it "respeita o scope informado para origens gravadas" do
      tenant = Tenant.create!(name: "Lead options #{SecureRandom.hex(3)}", slug: "lead-options-#{SecureRandom.hex(3)}")
      other_tenant = Tenant.create!(name: "Other lead options #{SecureRandom.hex(3)}", slug: "other-lead-options-#{SecureRandom.hex(3)}")
      create(:lead, tenant: tenant, origin: "Site Tenant")
      create(:lead, tenant: other_tenant, origin: "Outro Tenant")

      expect(described_class.origin_options(scope: tenant.leads, tenant: tenant)).to include("Site Tenant")
      expect(described_class.origin_options(scope: tenant.leads, tenant: tenant)).not_to include("Outro Tenant")
    end
  end

  describe ".tag_options" do
    it "respeita o scope informado para tags gravadas" do
      tenant = Tenant.create!(name: "Lead tags #{SecureRandom.hex(3)}", slug: "lead-tags-#{SecureRandom.hex(3)}")
      other_tenant = Tenant.create!(name: "Other lead tags #{SecureRandom.hex(3)}", slug: "other-lead-tags-#{SecureRandom.hex(3)}")
      create(:lead, tenant: tenant, tags: ["TenantTag"])
      create(:lead, tenant: other_tenant, tags: ["OtherTenantTag"])

      expect(described_class.tag_options(scope: tenant.leads)).to include("TenantTag")
      expect(described_class.tag_options(scope: tenant.leads)).not_to include("OtherTenantTag")
    end
  end

  describe "#preloaded_labels_for" do
    it "usa lead_labelings pre-carregadas sem consultar lead_labels novamente" do
      admin = create(:admin_user)
      other_admin = create(:admin_user, email: "lead-label-other-#{SecureRandom.hex(6)}@salute.test")
      lead = create(:lead)
      label = create(:lead_label, admin_user: admin, tenant: admin.tenant, name: "Quente", position: 2)
      other_label = create(:lead_label, admin_user: other_admin, tenant: other_admin.tenant, name: "Outro", position: 1)
      lead.lead_labelings.create!(lead_label: label, tenant: lead.tenant)
      lead.lead_labelings.create!(lead_label: other_label, tenant: lead.tenant)

      preloaded = described_class.includes(lead_labelings: :lead_label).find(lead.id)

      sql = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _started, _finished, _unique_id, payload|
        next if payload[:name] == "SCHEMA"
        sql << payload[:sql]
      end

      expect(preloaded.preloaded_labels_for(admin)).to eq([label])
      expect(sql.grep(/FROM "lead_labels"/)).to be_empty
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end
  end

  describe "destroy" do
    it "keeps SEO conversion events and clears the lead reference" do
      lead = create(:lead)
      event = SeoConversionEvent.create!(
        lead: lead,
        event_type: "lead_created",
        occurred_at: Time.current
      )

      expect { lead.destroy! }.not_to raise_error
      expect(event.reload.lead_id).to be_nil
    end
  end
end
