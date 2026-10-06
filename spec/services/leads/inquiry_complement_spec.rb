require "rails_helper"

RSpec.describe Leads::InquiryComplement do
  let(:tenant) { Tenant.create!(name: "Tenant complemento #{SecureRandom.hex(3)}", slug: "tenant-complemento-#{SecureRandom.hex(3)}") }
  let(:agent_profile) { tenant.profiles.find_by!(key: "agent") }
  let(:agent) { create(:admin_user, tenant: tenant, profile: agent_profile, active: true) }
  let(:rule) { create(:distribution_rule, tenant: tenant, require_active_checkin: false, pocket_active: true, pocket_time: 20) }

  before do
    LeadSetting.instance(tenant: tenant).update!(stickiness_match: "phone_or_email")
    allow(Leads::NotificationDispatcher).to receive(:notify_complement)
  end

  def distributed_lead(phone:, broker: agent, distribution_rule: rule, status: "Aguardando Aceite")
    lead = create(:lead, tenant: tenant, phone: phone, admin_user: broker, distribution_rule: distribution_rule, status: status)
    lead.activities.create!(kind: "distributed", metadata: { "admin_user_id" => broker.id })
    lead
  end

  it "agrega a consulta ao lead aberto dentro do pocket em vez de criar outro" do
    first = distributed_lead(phone: "5547999990000")
    first.update_columns(email: nil, client_email: nil)
    property = create(:habitation, tenant: tenant)
    inquiry = build(:lead, tenant: tenant, phone: "(47) 99999-0000", email: "novo@example.com", property_id: property.id, origin: "Site")

    target = described_class.dissolve_into_target!(inquiry)

    expect(target).to eq(first)
    expect(inquiry).to be_destroyed
    expect(first.reload.property_interests.map(&:habitation_id)).to include(property.id)
    expect(first.email).to eq("novo@example.com")
    expect(first.activities.where(kind: "inquiry_complemented").count).to eq(1)
    expect(Leads::NotificationDispatcher).to have_received(:notify_complement).with(first, property)
  end

  it "complementa mesmo quando o lead existente ainda aguarda aceite" do
    first = distributed_lead(phone: "5547999990000", status: "Aguardando Aceite")
    inquiry = build(:lead, tenant: tenant, phone: "5547999990000", origin: "Site")

    expect(described_class.target_for(inquiry)).to eq(first)
  end

  it "não complementa fora da janela do pocket" do
    first = distributed_lead(phone: "5547999990000")
    first.activities.where(kind: "distributed").update_all(created_at: 2.hours.ago)
    first.update_columns(created_at: 2.hours.ago)
    inquiry = build(:lead, tenant: tenant, phone: "5547999990000", origin: "Site")

    expect(described_class.target_for(inquiry)).to be_nil
  end

  it "não complementa lead arquivado ou finalizado" do
    archived = distributed_lead(phone: "5547999990001")
    archived.update_columns(archived_at: Time.current)
    lost = distributed_lead(phone: "5547999990002", status: "Perdido")

    expect(described_class.target_for(build(:lead, tenant: tenant, phone: "5547999990001"))).to be_nil
    expect(described_class.target_for(build(:lead, tenant: tenant, phone: "5547999990002"))).to be_nil
    expect(lost).to be_present
  end

  it "não complementa quando o dono está inativo nem sem regra de pocket" do
    distributed_lead(phone: "5547999990003")
    agent.update!(active: false)
    no_pocket_rule = create(:distribution_rule, tenant: tenant, pocket_active: false)
    other_agent = create(:admin_user, tenant: tenant, profile: agent_profile, active: true)
    distributed_lead(phone: "5547999990004", broker: other_agent, distribution_rule: no_pocket_rule)

    expect(described_class.target_for(build(:lead, tenant: tenant, phone: "5547999990003"))).to be_nil
    expect(described_class.target_for(build(:lead, tenant: tenant, phone: "5547999990004"))).to be_nil
  end

  it "prefere o lead aberto mais recente entre split legado" do
    old_broker = create(:admin_user, tenant: tenant, profile: agent_profile, active: true)
    old = distributed_lead(phone: "5547999990005", broker: old_broker)
    old.update_columns(created_at: 1.hour.ago)
    old.activities.where(kind: "distributed").update_all(created_at: 1.hour.ago)
    recent = distributed_lead(phone: "5547999990005", broker: agent)
    inquiry = build(:lead, tenant: tenant, phone: "5547999990005", origin: "Site")

    # Pocket de 20min: o antigo saiu da janela, o recente complementa.
    expect(described_class.target_for(inquiry)).to eq(recent)
  end

  it "não atravessa tenants" do
    other = Tenant.create!(name: "Outro #{SecureRandom.hex(3)}", slug: "outro-#{SecureRandom.hex(3)}")
    distributed_lead(phone: "5547999990006")
    inquiry = build(:lead, tenant: other, phone: "5547999990006", origin: "Site")

    expect(described_class.target_for(inquiry)).to be_nil
  end
end
