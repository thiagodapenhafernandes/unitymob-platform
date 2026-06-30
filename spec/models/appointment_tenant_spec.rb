require "rails_helper"

RSpec.describe Appointment, type: :model do
  def create_tenant_with_profile(name)
    tenant = Tenant.create!(name: name, slug: "#{name.parameterize}-#{SecureRandom.hex(3)}")
    profile = Profile.create!(tenant: tenant, name: "Operacional", axis: "vertical", position: 50)
    [tenant, profile]
  end

  it "rejeita responsável de outra conta" do
    tenant, profile = create_tenant_with_profile("Conta Compromisso A")
    other_tenant, other_profile = create_tenant_with_profile("Conta Compromisso B")
    owner = create(:admin_user, tenant: tenant, profile: profile)
    other_owner = create(:admin_user, tenant: other_tenant, profile: other_profile)

    appointment = described_class.new(
      tenant: tenant,
      admin_user: other_owner,
      title: "Visita",
      kind: "visita",
      status: "agendado",
      starts_at: 1.day.from_now
    )

    expect(appointment).not_to be_valid
    expect(appointment.errors[:admin_user]).to include("deve pertencer à mesma conta do compromisso")
    expect(owner.tenant_id).to eq(tenant.id)
  end

  it "rejeita lead e imóvel de outra conta" do
    tenant, profile = create_tenant_with_profile("Conta Compromisso C")
    other_tenant = Tenant.create!(name: "Conta Compromisso D", slug: "conta-compromisso-d-#{SecureRandom.hex(3)}")
    owner = create(:admin_user, tenant: tenant, profile: profile)
    lead = build(:lead, tenant: other_tenant)
    habitation = build(:habitation, tenant: other_tenant)

    appointment = described_class.new(
      tenant: tenant,
      admin_user: owner,
      lead: lead,
      habitation: habitation,
      title: "Visita",
      kind: "visita",
      status: "agendado",
      starts_at: 1.day.from_now
    )

    expect(appointment).not_to be_valid
    expect(appointment.errors[:lead]).to include("deve pertencer à mesma conta do compromisso")
    expect(appointment.errors[:habitation]).to include("deve pertencer à mesma conta do compromisso")
  end
end
