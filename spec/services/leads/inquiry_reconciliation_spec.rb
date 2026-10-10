require "rails_helper"

RSpec.describe Leads::InquiryReconciliation do
  let(:tenant) { create(:admin_user).tenant }
  let(:actor) { create(:admin_user, tenant: tenant) }
  let(:habitation) { create(:habitation, tenant: tenant, codigo: "REC-1") }
  let(:target) { create(:lead, tenant: tenant, admin_user: actor) }
  let(:inquiry) do
    create(:lead, tenant: tenant, admin_user: actor,
      other_information: { "unverified_inquiry" => true, "share_collection_id" => 1 })
  end

  it "funde interesses e atividades no destino e descarta a apuração" do
    inquiry.property_interests.create!(tenant: tenant, habitation: habitation)
    LeadActivity.log!(lead: inquiry, kind: "property_interest", metadata: {})

    result = described_class.reconcile!(inquiry: inquiry, target: target, actor: actor)

    expect(result).to eq(target)
    expect(target.property_interests.where(habitation: habitation).count).to eq(1)
    expect(target.activities.where(kind: %w[property_interest inquiry_complemented inquiry_reconciled]).count).to eq(3)
    expect(Lead.find_by(id: inquiry.id)).to be_nil
    expect(inquiry.complemented_into_id).to eq(target.id)
  end

  it "não duplica interesse que o destino já tem" do
    target.property_interests.create!(tenant: tenant, habitation: habitation)
    inquiry.property_interests.create!(tenant: tenant, habitation: habitation)

    described_class.reconcile!(inquiry: inquiry, target: target, actor: actor)

    expect(target.property_interests.where(habitation: habitation).count).to eq(1)
  end

  it "rejeita destino de outra conta" do
    other_tenant = Tenant.create!(name: "Outra #{SecureRandom.hex(3)}", slug: "outra-#{SecureRandom.hex(3)}")
    other = create(:lead, tenant: other_tenant)

    expect { described_class.reconcile!(inquiry: inquiry, target: other, actor: actor) }
      .to raise_error(Leads::InquiryReconciliation::Error, /mesma conta/)
  end

  it "rejeita registro que não é apuração e destino igual ou arquivado" do
    plain = create(:lead, tenant: tenant)
    archived = create(:lead, tenant: tenant, archived_at: Time.current)

    expect { described_class.reconcile!(inquiry: plain, target: target, actor: actor) }
      .to raise_error(Leads::InquiryReconciliation::Error, /não-verificada/)
    expect { described_class.reconcile!(inquiry: inquiry, target: inquiry, actor: actor) }
      .to raise_error(Leads::InquiryReconciliation::Error, /outro lead/)
    expect { described_class.reconcile!(inquiry: inquiry, target: archived, actor: actor) }
      .to raise_error(Leads::InquiryReconciliation::Error, /arquivado/)
  end
end
