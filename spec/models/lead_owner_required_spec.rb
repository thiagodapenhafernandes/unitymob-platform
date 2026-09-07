require "rails_helper"
RSpec.describe "Responsabilidade do lead" do
  let(:tenant) { Tenant.create!(name: "Owner guard", slug: "owner-#{SecureRandom.hex(5)}") }
  let(:broker) { create(:admin_user, tenant: tenant) }
  let(:lead) { create(:lead, tenant: tenant, admin_user: nil) }

  it "exige corretor para atendimento e permite atribuí-lo junto com a etapa" do
    lead.status = Lead.status_value(:em_atendimento, tenant: tenant)
    expect(lead).not_to be_valid
    expect(lead.errors[:admin_user]).to be_present
    lead.admin_user = broker
    expect(lead).to be_valid
  end

  %i[task appointment].each do |kind|
    it "bloqueia #{kind} de lead sem corretor, preservando atividades pessoais e encerramento" do
      activity = build(kind, tenant: tenant, lead: lead, admin_user: broker)
      expect(activity).not_to be_valid
      expect(activity.errors[:lead]).to be_present
      activity.lead = nil
      expect(activity).to be_valid
      activity.save!
      activity.update_columns(lead_id: lead.id)
      activity.reload
      activity.status = kind == :task ? 'cancelada' : 'cancelado'
      expect(activity).to be_valid
    end
  end
end
