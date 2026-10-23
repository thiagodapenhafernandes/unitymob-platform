require "rails_helper"

RSpec.describe Lead, ".commercial" do
  let(:tenant) { create(:admin_user).tenant }

  it "preserva flags legadas, filtros e paginação sem modificar os registros" do
    leads = [{}, { "whatsapp_service_contact" => nil }, { "whatsapp_service_contact" => false },
             { "whatsapp_service_contact" => "false" }, { "whatsapp_service_contact" => true },
             { "whatsapp_service_contact" => "true" }].map do |info|
      create(:lead, tenant: tenant, other_information: info)
    end
    scope = tenant.leads.where(id: leads.map(&:id))
    original_attributes = leads.map(&:attributes)
    expected = scope.where("COALESCE(other_information ->> 'whatsapp_service_contact', 'false') <> 'true'").order(:id).pluck(:id)

    expect(scope.commercial.order(:id).pluck(:id)).to eq(expected)
    expect(scope.order(id: :desc).limit(2).commercial.pluck(:id)).to eq(expected.reverse.first(2))
    expect(scope.commercial.where(id: leads.last(2).map(&:id))).to be_empty
    expect(leads.map { |lead| lead.reload.attributes }).to eq(original_attributes)
  end

  it "preserva isolamento por tenant e usa o índice parcial" do
    foreign_tenant = Tenant.create!(name: "Outra", slug: "commercial-#{SecureRandom.hex(4)}")
    own = create(:lead, tenant: tenant)
    create(:lead, tenant: foreign_tenant)
    create(:lead, tenant: tenant, other_information: { "whatsapp_service_contact" => true })
    ActiveRecord::Base.connection.execute("SET LOCAL enable_seqscan = off")

    expect(tenant.leads.commercial.pluck(:id)).to eq([own.id])
    expect(tenant.leads.commercial.explain).to include("idx_leads_whatsapp_service_contacts")
  end

  it "inclui registros legados com JSON nulo" do
    lead = create(:lead, tenant: tenant)
    lead.update_columns(other_information: nil)
    expect(tenant.leads.commercial.pluck(:id)).to eq([lead.id])
  end
end
