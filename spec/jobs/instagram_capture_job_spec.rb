require "rails_helper"

RSpec.describe Instagram::CaptureJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:integration) { create(:user_meta_integration) }
  let(:tenant) { integration.tenant }
  let(:page) { create(:meta_facebook_page, user_meta_integration: integration, instagram_id: "12345", instagram_enabled: true) }
  let(:settings) { Instagram::CaptureSettings.new(page, tenant: tenant) }

  before do
    integration.update!(selected_page_ids: [page.page_id])
    allow(Instagram::Reply).to receive(:call) { Struct.new(:occurred_at).new(Time.current) }
    allow(Leads::RoutingService).to receive(:route!).and_call_original
  end

  def inbound(id, body, referral: nil)
    InstagramDirectJob.perform_now("12345", {
      "sender" => { "id" => "98765" }, "recipient" => { "id" => "12345" },
      "message" => { "mid" => id, "text" => body, "referral" => referral }
    })
    tenant.leads.find_by!(instagram_scoped_id: "98765")
  end

  it "retém até confirmar nome e telefone com DDD e libera uma única vez" do
    settings.save(campaign_id: "default", enabled: true, name_prompt: "Seu nome?", phone_prompt: "Seu telefone?")
    lead = inbound("first", "Quero saber mais")
    expect(lead).to be_instagram_capture_pending
    expect(Leads::RoutingService).not_to have_received(:route!)

    described_class.perform_now(tenant.id, lead.id)
    described_class.perform_now(tenant.id, lead.id)
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: "Seu nome?", admin_user: nil).once

    inbound("name", "Maria Silva")
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload.client_name).to eq("Maria Silva")
    inbound("invalid", "998887777")
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload).to be_instagram_capture_pending
    expect(Leads::RoutingService).not_to have_received(:route!)

    inbound("phone", "(47) 99888-7777")
    described_class.perform_now(tenant.id, lead.id)
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload.phone).to eq("5547998887777")
    expect(lead).not_to be_instagram_capture_pending
    expect(Leads::RoutingService).to have_received(:route!).with(lead).once
  end

  it "usa a campanha confirmada em preferência ao padrão do perfil" do
    integration.update!(ad_accounts: { "999" => "Conta" })
    settings.save(campaign_id: "default", enabled: true, name_prompt: "Nome padrão?", phone_prompt: "")
    settings.save(campaign_id: "56789", enabled: true, name_prompt: "Nome da campanha?", phone_prompt: "")
    graph = instance_double(Facebook::MetaService)
    allow(Facebook::MetaService).to receive(:new).with(integration.access_token).and_return(graph)
    allow(graph).to receive(:ad_attribution).with("123456", account_ids: ["999"])
      .and_return("meta_campaign_id" => "56789", "meta_ad_id" => "123456")

    lead = inbound("ad", "Olá", referral: { "ad_id" => "123456" })
    described_class.perform_now(tenant.id, lead.id)
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: "Nome da campanha?", admin_user: nil)
    expect(lead.reload.other_information["meta_campaign_id"]).to eq("56789")
  end

  it "libera após o prazo do e-mail opcional sem resposta" do
    settings.save(campaign_id: "default", enabled: true, name_prompt: "", phone_prompt: "", ask_email: true)
    lead = inbound("first", "Olá")
    described_class.perform_now(tenant.id, lead.id)
    inbound("name", "Maria Silva")
    described_class.perform_now(tenant.id, lead.id)
    inbound("phone", "(47) 99888-7777")
    expect { described_class.perform_now(tenant.id, lead.id) }
      .to have_enqueued_job(described_class).with(tenant.id, lead.id)
    expect(lead.reload).to be_instagram_capture_pending
    expect(lead.phone).to eq("5547998887777")

    travel described_class::EMAIL_WAIT + 1.second do
      described_class.perform_now(tenant.id, lead.id)
      described_class.perform_now(tenant.id, lead.id)
    end
    expect(lead.reload).not_to be_instagram_capture_pending
    expect(lead.email).to be_blank
    expect(Leads::RoutingService).to have_received(:route!).with(lead).once
  end

  it "não inicia captação para perfis sem configuração ativa" do
    lead = nil
    expect { lead = inbound("organic", "Olá") }.not_to have_enqueued_job(Instagram::CaptureJob)
    expect(lead).not_to be_instagram_capture_pending
  end
end
