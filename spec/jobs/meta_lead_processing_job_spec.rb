require "rails_helper"

RSpec.describe MetaLeadProcessingJob, type: :job do
  around do |example|
    Lead.skip_callback(:commit, :after, :route_lead)
    example.run
  ensure
    Lead.set_callback(:commit, :after, :route_lead)
  end

  it "cria o lead no tenant do usuario dono da integracao Meta" do
    tenant = Tenant.create!(name: "Conta Meta #{SecureRandom.hex(3)}", slug: "conta-meta-#{SecureRandom.hex(3)}")
    admin = create(:admin_user, :admin, tenant: tenant)
    integration = create(:user_meta_integration, admin_user: admin, access_token: "user-token")
    page = create(:meta_facebook_page, user_meta_integration: integration, page_id: "page-meta-tenant", access_token: "page-token")
    create(:meta_lead_form, meta_facebook_page: page, form_id: "form-meta-tenant", name: "Captação Meta Tenant")
    create(:meta_lead_form, form_id: "form-meta-outro", name: "Formulário de outra integração")
    service = instance_double(
      Facebook::MetaService,
      get_lead_details: {
        "id" => "lead-meta-1",
        "field_data" => [
          { "name" => "full_name", "values" => ["Maria Meta"] },
          { "name" => "email", "values" => ["maria@example.com"] },
          { "name" => "phone_number", "values" => ["5547999990000"] }
        ]
      }
    )

    allow(Facebook::MetaService).to receive(:new).with("page-token").and_return(service)

    expect {
      described_class.perform_now("lead-meta-1", "page-meta-tenant", "form-meta-tenant")
    }.to change { tenant.leads.count }.by(1)

    lead = tenant.leads.last
    expect(lead.admin_user).to eq(admin)
    expect(lead.name).to eq("Maria Meta")
    expect(lead.phone).to eq("5547999990000")
    expect(lead.product).to eq("Captação Meta Tenant")
    expect(lead.other_information["meta_page_id"]).to eq("page-meta-tenant")
  end
end
