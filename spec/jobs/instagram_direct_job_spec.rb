require "rails_helper"
RSpec.describe InstagramDirectJob do
  let(:integration) { create(:user_meta_integration) }
  let!(:page) { create(:meta_facebook_page, user_meta_integration: integration, instagram_id: "12345", instagram_enabled: true) }
  let(:event) { {"sender" => {"id" => "98765"}, "recipient" => {"id" => "12345"}, "timestamp" => 1_789_000_000_000, "message" => {"mid" => "mid-1", "text" => "Olá"}} }

  it "recebe sem telefone, vincula pela identidade e deduplica a entrega" do
    expect do
      2.times { described_class.perform_now("12345", event) }
    end.to have_enqueued_job(Instagram::ProfileEnrichmentJob).once
    lead = integration.tenant.leads.find_by!(instagram_scoped_id: "98765")
    expect(lead.origin).to eq("Instagram Direct")
    expect(lead.phone).to be_blank
    expect(lead.instagram_messages.count).to eq(1)
    lead.update!(name: "Nome confirmado", origin: "Site")
    event["message"]["mid"] = "mid-2"
    described_class.perform_now("12345", event)
    expect(lead.reload.name).to eq("Nome confirmado")
    expect(lead.origin).to eq("Site")
    expect(lead.instagram_messages.count).to eq(2)
  end

  it "bloqueia remetente interno antes de criar lead, inclusive após mudar o @ na Meta" do
    member = integration.admin_user
    member.update!(instagram_username: " @Corretor.BC ")
    graph = instance_double(Koala::Facebook::API)
    allow(Koala::Facebook::API).to receive(:new).with(page.access_token).and_return(graph)
    allow(graph).to receive(:get_object).with("98765", fields: "username").and_return("username" => "corretor.bc")

    expect do
      2.times { described_class.perform_now("12345", event) }
    end.not_to change(Lead, :count)
    expect(graph).to have_received(:get_object).once
    expect(member.reload.instagram_direct_ids).to eq("12345" => "98765")
    member.update!(instagram_username: "outro.perfil")
    expect(member.reload.instagram_direct_ids).to be_empty
  end

  it "não bloqueia um @ cadastrado apenas em outra conta" do
    create(:admin_user, instagram_username: "corretor.bc")

    expect { described_class.perform_now("12345", event) }.to change { integration.tenant.leads.count }.by(1)
  end

  it "ignora eco, destinatário incorreto e perfil desativado" do
    event["message"]["is_echo"] = true
    expect { described_class.perform_now("12345", event) }.not_to change(InstagramMessage, :count)
    event["message"].delete("is_echo")
    expect { described_class.perform_now("other", event) }.not_to change(InstagramMessage, :count)
    page.update!(instagram_enabled: false)
    expect { described_class.perform_now("12345", event) }.not_to change(InstagramMessage, :count)
  end

  it "não vincula por nome nem mistura o mesmo remetente entre contas" do
    other = create(:user_meta_integration, admin_user: create(:admin_user, tenant: Tenant.create!(name: "Outra", slug: "ig-other")))
    create(:meta_facebook_page, user_meta_integration: other, instagram_id: "54321", instagram_enabled: true)
    described_class.perform_now("12345", event)
    event["recipient"]["id"] = "54321"
    described_class.perform_now("54321", event)
    expect(integration.tenant.leads.where(instagram_scoped_id: "98765").count).to eq(1)
    expect(other.tenant.leads.where(instagram_scoped_id: "98765").count).to eq(1)
  end
end
