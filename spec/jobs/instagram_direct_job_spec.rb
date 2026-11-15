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
  it "registra a página Meta mesmo no Direct orgânico, antes de receber campanha" do
    integration.update!(selected_page_ids: [page.page_id])
    described_class.perform_now("12345", event)
    lead = integration.tenant.leads.find_by!(instagram_scoped_id: "98765")
    expect(lead.other_information["meta_page_id"]).to eq(page.page_id)
    expect(lead.instagram_messages.sole.context["meta_facebook_page_id"]).to eq(page.id)
    expect(lead.other_information["meta_campaign_id"]).to be_nil
  end

  it "preserva menções, mídia e resposta ao story sem inventar texto do cliente" do
    event["message"].delete("text")
    event["message"]["attachments"] = [{"type" => "story_mention", "payload" => {"url" => "https://lookaside.fbsbx.com/story"}}]
    event["message"]["reply_to"] = {"story" => {"id" => "123", "url" => "https://lookaside.fbsbx.com/reply"}}
    described_class.perform_now("12345", event)
    message = integration.tenant.leads.find_by!(instagram_scoped_id: "98765").instagram_messages.sole
    expect(message.body).to eq("")
    expect(message.context).to include("story_id" => "123", "story_url" => "https://lookaside.fbsbx.com/reply",
      "attachments" => [{"type" => "story_mention", "url" => "https://lookaside.fbsbx.com/story"}])
    expect(message.conversation_text).to include("Mencionou a conta", "Resposta a story")
    expect(message.automation_input?).to be(false)
  end

  it "guarda a referência do catálogo na mensagem sem transformar a menção em pedido" do
    property = create(:habitation, tenant: integration.tenant, codigo: '9705')
    event['message'].delete('text')
    event['message']['attachments'] = [{'type' => 'ig_reel', 'payload' => {'title' => ('Descrição do anúncio. ' * 110) + 'Cód. 9705'}}]
    described_class.perform_now('12345', event)
    message = integration.tenant.leads.find_by!(instagram_scoped_id: '98765').instagram_messages.sole
    expect(message.context['property_code']).to eq(property.codigo)
    expect(message.automation_input?).to be(false)
  end

  it "não concilia contato ambíguo e preserva ambos os cadastros" do
    2.times { create(:lead, tenant: integration.tenant, phone: '47998887777', skip_automatic_routing: true) }
    described_class.perform_now('12345', event)
    provisional = integration.tenant.leads.find_by!(instagram_scoped_id: '98765')
    event['message'] = {'mid' => 'phone', 'text' => 'Meu WhatsApp é (47) 99888-7777'}
    expect { described_class.perform_now('12345', event) }.not_to change(Lead, :count)
    expect(provisional.reload.other_information['instagram_identity_conflict']).to be(true)
  end

  it "aplica phone_and_email da conta e não usa contatos de outro tenant" do
    LeadSetting.instance(tenant: integration.tenant).update!(stickiness_match: 'phone_and_email')
    existing = create(:lead, tenant: integration.tenant, phone: '47998887777', email: 'maria@example.test', skip_automatic_routing: true)
    event['message'] = {'mid' => 'phone', 'text' => 'Meu WhatsApp é (47) 99888-7777'}
    described_class.perform_now('12345', event)
    provisional = integration.tenant.leads.find_by!(instagram_scoped_id: '98765')
    expect(provisional.id).not_to eq(existing.id)
    provisional.update_columns(phone: '47998887777')
    event['message'] = {'mid' => 'email', 'text' => 'Meu email é maria@example.test'}
    described_class.perform_now('12345', event)
    expect(existing.reload.instagram_scoped_id).to eq('98765')
  end

  it "não identifica por telefone um cadastro de outra conta" do
    other = Tenant.create!(name: 'Outro contato', slug: 'ig-phone-isolation')
    foreign = create(:lead, tenant: other, phone: '47998887777', skip_automatic_routing: true)
    event['message'] = {'mid' => 'contact', 'text' => 'Meu WhatsApp é (47) 99888-7777'}
    described_class.perform_now('12345', event)
    own = integration.tenant.leads.find_by!(instagram_scoped_id: '98765')
    expect(own.id).not_to eq(foreign.id)
    expect(foreign.reload.instagram_scoped_id).to be_nil
  end

  it "não desfaz um cadastro Instagram que já está com responsável" do
    owner = create(:admin_user, :admin, tenant: integration.tenant)
    existing = create(:lead, tenant: integration.tenant, phone: '47998887777', skip_automatic_routing: true)
    described_class.perform_now('12345', event)
    provisional = integration.tenant.leads.find_by!(instagram_scoped_id: '98765')
    provisional.update!(admin_user: owner, phone: '47998887776')
    event['message'] = {'mid' => 'contact', 'text' => 'Meu WhatsApp é (47) 99888-7777'}
    expect { described_class.perform_now('12345', event) }.not_to change(Lead, :count)
    expect(provisional.reload).to have_attributes(admin_user_id: owner.id, instagram_scoped_id: '98765')
    expect(existing.reload.instagram_scoped_id).to be_nil
    expect(provisional.other_information['instagram_identity_conflict']).to be(true)
  end

end
