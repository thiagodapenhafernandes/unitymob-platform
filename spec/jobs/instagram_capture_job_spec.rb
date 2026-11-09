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

  it "mantém o @ provisório e responde ao contexto sem tratar perguntas como nome ou repetir o pedido" do
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: {"enabled" => true, "sdr_enabled" => true})
    lead = inbound("first", "Oi")
    lead.update_columns(other_information: lead.other_information.deep_merge("instagram_profile" => {"username" => "ednadgazevedo"}))
    described_class.perform_now(tenant.id, lead.id)
    catalog = instance_double(Instagram::CatalogReply, call: "A equipe confirma as condições deste imóvel.")
    allow(Instagram::CatalogReply).to receive(:new).and_return(catalog)
    inbound("question", "Sobre esse apto do anúncio em cima do shopping.")
    2.times { described_class.perform_now(tenant.id, lead.id) }
    expect(lead.reload.client_name).to be_blank
    expect(lead.display_name).to eq("@ednadgazevedo")
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: Instagram::CaptureSettings::DEFAULT_NAME_PROMPT, admin_user: nil, typing: true).once
    expect(Instagram::Reply).not_to have_received(:call).with(lead: lead, body: Instagram::CaptureSettings::DEFAULT_PHONE_PROMPT, admin_user: nil, typing: true)
    expect(catalog).to have_received(:call).once
  end

  it "aproveita nome e telefone de mensagens em sequência sem perder dados nem repetir o cadastro" do
    settings.save(campaign_id: "default", enabled: true, name_prompt: "", phone_prompt: "")
    lead = inbound("first", "Oi")
    described_class.perform_now(tenant.id, lead.id)
    inbound("name", "Me chamo Edna")
    inbound("phone", "Meu WhatsApp é (47) 99888-7777")
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload).to have_attributes(client_name: "Edna", phone: "5547998887777")
    expect(lead).not_to be_instagram_capture_pending
    expect(Instagram::Reply).not_to have_received(:call).with(lead: lead, body: Instagram::CaptureSettings::DEFAULT_PHONE_PROMPT, admin_user: nil, typing: true)
  end

  it "respeita a opção de continuar no Instagram sem telefone e não reprocessa a recusa" do
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: {"enabled" => true, "sdr_enabled" => true})
    lead = inbound("first", "Oi")
    described_class.perform_now(tenant.id, lead.id)
    inbound("skip", "Prefiro continuar por aqui")
    2.times { described_class.perform_now(tenant.id, lead.id) }
    expect(lead.reload.client_name).to be_blank
    expect(lead.phone).to be_blank
    expect(lead).not_to be_instagram_capture_pending
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: "Claro, podemos continuar pelo Instagram.", admin_user: nil, typing: true).once
  end

  it "não perde a resposta que chega durante o envio da pergunta" do
    settings.save(campaign_id: "default", enabled: true, name_prompt: "", phone_prompt: "")
    lead = inbound("first", "Oi")
    described_class.perform_now(tenant.id, lead.id)
    inbound("name", "Edna")
    # Timestamp do cliente pode anteceder a confirmação de envio da pergunta.
    lead.instagram_messages.inbound.order(:id).last.update!(occurred_at: 2.seconds.ago)
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload.client_name).to eq("Edna")
  end

  it "não pede novamente os dados já fornecidos na primeira mensagem" do
    settings.save(campaign_id: "default", enabled: true, name_prompt: "", phone_prompt: "")
    lead = inbound("first", "Me chamo Edna, meu WhatsApp é (47) 99888-7777")
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload).to have_attributes(client_name: "Edna", name: "Edna", phone: "5547998887777")
    expect(lead).not_to be_instagram_capture_pending
    expect(Instagram::Reply).not_to have_received(:call).with(lead: lead, body: Instagram::CaptureSettings::DEFAULT_NAME_PROMPT, admin_user: nil, typing: true)
  end

  it "retém até confirmar nome e telefone com DDD e libera uma única vez" do
    settings.save(campaign_id: "default", enabled: true, name_prompt: "Seu nome?", phone_prompt: "Seu telefone?")
    lead = inbound("first", "Quero saber mais")
    expect(lead).to be_instagram_capture_pending
    expect(Leads::RoutingService).not_to have_received(:route!)

    described_class.perform_now(tenant.id, lead.id)
    described_class.perform_now(tenant.id, lead.id)
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: "Seu nome?", admin_user: nil, typing: true).once

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
    expect(Instagram::Reply).to have_received(:call).with(
      lead: lead, body: Instagram::CaptureSettings::DEFAULT_THANK_YOU.gsub("{primeiro_nome}", "Maria"),
      admin_user: nil, typing: true
    ).once
    expect(lead.reload.phone).to eq("5547998887777")
    expect(lead).not_to be_instagram_capture_pending
    expect(Leads::RoutingService).to have_received(:route!).with(lead).once
  end

  it "continua uma captação concluída com SDR ativo sem repetir a resposta" do
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: { "enabled" => true, "sdr_enabled" => true })
    lead = inbound("first", "Oi")
    described_class.perform_now(tenant.id, lead.id)
    inbound("name", "Maria Silva")
    described_class.perform_now(tenant.id, lead.id)
    inbound("phone", "(47) 99888-7777")
    described_class.perform_now(tenant.id, lead.id)

    catalog = instance_double(Instagram::CatalogReply)
    allow(Instagram::CatalogReply).to receive(:new).and_return(catalog)
    expect(catalog).to receive(:call).with(array_including({ role: "cliente", text: "Quero um apartamento" }), first_turn: true).once.and_return("Em qual bairro?")
    inbound("interest", "Quero um apartamento")
    2.times { described_class.perform_now(tenant.id, lead.id) }
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: "Em qual bairro?", admin_user: nil, typing: true).once
    expect(Leads::RoutingService).to have_received(:route!).with(lead).once
  end

  it "reutiliza o histórico de um Direct cadastrado antes de ativar o SDR" do
    lead = inbound("old", "Busco uma casa em Itajaí")
    lead.instagram_messages.create!(message_id: "old-reply", body: "Qual bairro?", direction: "outbound", occurred_at: Time.current)
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: { "enabled" => true, "sdr_enabled" => true })

    catalog = instance_double(Instagram::CatalogReply)
    allow(Instagram::CatalogReply).to receive(:new).and_return(catalog)
    expect(catalog).to receive(:call).with([
      { role: "cliente", text: "Busco uma casa em Itajaí" },
      { role: "assistente", text: "Qual bairro?" },
      { role: "cliente", text: "Centro" }
    ], first_turn: true).and_return("Qual é sua faixa de preço?")
    expect(inbound("return", "Centro").id).to eq(lead.id)

    described_class.perform_now(tenant.id, lead.id)
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: "Qual é sua faixa de preço?", admin_user: nil, typing: true)
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
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: "Nome da campanha?", admin_user: nil, typing: true)
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

  { "maria@example.com" => "maria@example.com", "Pular" => nil }.each do |answer, expected_email|
    it "libera a distribuição uma vez após a resposta opcional #{answer}" do
      settings.save(campaign_id: "default", enabled: true, name_prompt: "", phone_prompt: "", ask_email: true)
      lead = inbound("first", "Olá")
      described_class.perform_now(tenant.id, lead.id)
      inbound("name", "Maria Silva")
      described_class.perform_now(tenant.id, lead.id)
      inbound("phone", "(47) 99888-7777")
      described_class.perform_now(tenant.id, lead.id)
      expect(Instagram::Reply).to have_received(:call).with(
        lead: lead, body: Instagram::CaptureSettings::DEFAULT_EMAIL_PROMPT, admin_user: nil, typing: true
      ).once
      expect(Leads::RoutingService).not_to have_received(:route!)

      inbound("email", answer)
      2.times { described_class.perform_now(tenant.id, lead.id) }
      expect(lead.reload.email.presence).to eq(expected_email)
      expect(Leads::RoutingService).to have_received(:route!).with(lead).once
    end
  end

  it "não inicia captação para perfis sem configuração ativa" do
    lead = nil
    expect { lead = inbound("organic", "Olá") }.not_to have_enqueued_job(Instagram::CaptureJob)
    expect(lead).not_to be_instagram_capture_pending
  end
end
