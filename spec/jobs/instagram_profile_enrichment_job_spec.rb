require "rails_helper"

RSpec.describe Instagram::ProfileEnrichmentJob do
  let(:integration) { create(:user_meta_integration) }
  let(:tenant) { integration.tenant }
  let!(:page) { create(:meta_facebook_page, user_meta_integration: integration, instagram_id: "12345", instagram_enabled: true) }
  let!(:lead) do
    create(:lead, tenant: tenant, name: described_class::DEFAULT_NAME,
      instagram_account_id: "12345", instagram_scoped_id: "98765", skip_automatic_routing: true)
  end
  let(:graph) { instance_double(Koala::Facebook::API) }

  before do
    integration.update!(selected_page_ids: [page.page_id])
    allow(Koala::Facebook::API).to receive(:new).with(page.access_token).and_return(graph)
    allow(graph).to receive(:get_object).with("98765", fields: "name,username")
      .and_return("name" => "Nome da Meta", "username" => "perfil.teste")
  end

  it "completa o perfil genérico preservando o restante do cadastro" do
    lead.update_columns(email: "cliente@example.com", other_information: { "instagram_entry" => { "story_id" => "123" } })
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload).to have_attributes(name: "@perfil.teste", instagram_username: "perfil.teste", email: "cliente@example.com")
    expect(lead.other_information.dig("instagram_entry", "story_id")).to eq("123")
  end

  it "preserva nome confirmado e usuário previamente preenchido" do
    lead.update_columns(client_name: "Nome confirmado", other_information: { "instagram_profile" => { "username" => "existente" } })
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload).to have_attributes(name: described_class::DEFAULT_NAME, display_name: "Nome confirmado", instagram_username: "existente")
  end

  it "não consulta a Meta se a página saiu da seleção da conta" do
    integration.update!(selected_page_ids: [])
    described_class.perform_now(tenant.id, lead.id)
    expect(graph).not_to have_received(:get_object)
    expect(lead.reload.instagram_username).to be_nil
  end
end
