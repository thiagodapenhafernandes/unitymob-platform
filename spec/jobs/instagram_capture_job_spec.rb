require "rails_helper"

RSpec.describe Instagram::CaptureJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:integration) { create(:user_meta_integration) }
  let(:tenant) { integration.tenant }
  let(:page) { create(:meta_facebook_page, user_meta_integration: integration, instagram_id: "12345", instagram_enabled: true) }
  let(:settings) { Instagram::CaptureSettings.new(page, tenant: tenant) }

  before do
    integration.update!(selected_page_ids: [page.page_id])
    allow(Instagram::Reply).to receive(:with_typing).and_wrap_original { |_method, *_args, &block| block.call }
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

  it "mantém o @ provisório e solicita os dados antes de responder sobre o imóvel" do
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
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: Instagram::CaptureSettings::DEFAULT_NAME_PROMPT, admin_user: nil, typing: false).once
    expect(Instagram::Reply).not_to have_received(:call).with(lead: lead, body: Instagram::CaptureSettings::DEFAULT_PHONE_PROMPT, admin_user: nil, typing: false)
    expect(catalog).not_to have_received(:call)
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
    expect(Instagram::Reply).not_to have_received(:call).with(lead: lead, body: Instagram::CaptureSettings::DEFAULT_PHONE_PROMPT, admin_user: nil, typing: false)
  end

  it "explica a necessidade dos dados sem liberar a distribuição quando a pessoa não informa telefone" do
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: {"enabled" => true, "sdr_enabled" => true})
    lead = inbound("first", "Oi")
    described_class.perform_now(tenant.id, lead.id)
    inbound("skip", "Prefiro continuar por aqui")
    2.times { described_class.perform_now(tenant.id, lead.id) }
    expect(lead.reload.client_name).to be_blank
    expect(lead.phone).to be_blank
    expect(lead).to be_instagram_capture_pending
    expect(Leads::RoutingService).not_to have_received(:route!)
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: a_string_including("nome e telefone com DDD"), admin_user: nil, typing: false).once
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
    expect(Instagram::Reply).not_to have_received(:call).with(lead: lead, body: Instagram::CaptureSettings::DEFAULT_NAME_PROMPT, admin_user: nil, typing: false)
  end

  it "só libera após obter os dois dados e então responde à dúvida que ficou pendente" do
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: {"enabled" => true, "sdr_enabled" => true})
    lead = inbound("first", "Oi")
    described_class.perform_now(tenant.id, lead.id)
    catalog = instance_double(Instagram::CatalogReply, call: "O imóvel aceita financiamento.")
    allow(Instagram::CatalogReply).to receive(:new).and_return(catalog)
    inbound("question", "Como é a forma de pagamento?")
    described_class.perform_now(tenant.id, lead.id)
    expect(catalog).not_to have_received(:call)
    inbound("phone", "(47) 99888-7777")
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload).to be_instagram_capture_pending
    expect(Leads::RoutingService).not_to have_received(:route!)
    inbound("name", "Me chamo Edna")
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload).not_to be_instagram_capture_pending
    expect(catalog).to have_received(:call).with(array_including({role: "cliente", text: "Como é a forma de pagamento?"}), first_turn: true).once
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: "O imóvel aceita financiamento.", admin_user: nil, typing: false).once
  end

  it "registra encaminhamento e avisa o corretor uma única vez quando faltam informações" do
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: {"enabled" => true, "sdr_enabled" => true})
    lead = inbound("first", "Como é a forma de pagamento?")
    described_class.perform_now(tenant.id, lead.id)
    catalog = instance_double(Instagram::CatalogReply, call: Instagram::CatalogReply::HANDOFF)
    allow(Instagram::CatalogReply).to receive(:new).and_return(catalog)
    allow(Leads::RoutingService).to receive(:route!) { |record| record.update_columns(admin_user_id: integration.admin_user_id) }
    allow(Leads::NotificationDispatcher).to receive(:push_to)
    inbound("contact", "Edna (47) 99888-7777")
    2.times { described_class.perform_now(tenant.id, lead.id) }
    expect(lead.reload.other_information.dig('instagram_capture', 'sdr_cursor')).to be_nil
    expect(lead.activities.where(kind: 'note').where("metadata ? 'instagram_handoff_cursor'").count).to eq(1)
    expect(Leads::NotificationDispatcher).to have_received(:push_to).with(integration.admin_user, hash_including(event: 'instagram_handoff')).once
    expect(Leads::RoutingService).to have_received(:route!).with(lead).once
  end

  it "retoma a coleta antes de responder a um contato antigo que ainda não tem dados" do
    lead = inbound("old-contact", "Oi")
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: {"enabled" => true, "sdr_enabled" => true})
    expect(Instagram::CatalogReply).not_to receive(:new)
    inbound("question", "Como é a forma de pagamento?")
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload).to be_instagram_capture_pending
    expect(lead.other_information.dig('instagram_capture', 'step')).to eq('name')
  end

  it "retém até confirmar nome e telefone com DDD e libera uma única vez" do
    settings.save(campaign_id: "default", enabled: true, name_prompt: "Seu nome?", phone_prompt: "Seu telefone?")
    lead = inbound("first", "Quero saber mais")
    expect(lead).to be_instagram_capture_pending
    expect(Leads::RoutingService).not_to have_received(:route!)

    described_class.perform_now(tenant.id, lead.id)
    described_class.perform_now(tenant.id, lead.id)
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: "Seu nome?", admin_user: nil, typing: false).once

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
      admin_user: nil, typing: false
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
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: "Em qual bairro?", admin_user: nil, typing: false).once
    expect(Leads::RoutingService).not_to have_received(:route!)
    expect(lead.reload).to be_instagram_automation_holding
    expect(lead.admin_user_id).to be_nil
  end

  it "reutiliza o histórico de um Direct cadastrado antes de ativar o SDR" do
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: {"enabled" => false})
    lead = inbound("old", "Busco uma casa em Itajaí")
    lead.update_columns(client_name: "Maria Silva", phone: "5547998887777")
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
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: "Qual é sua faixa de preço?", admin_user: nil, typing: false)
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
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: "Nome da campanha?", admin_user: nil, typing: false)
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
        lead: lead, body: Instagram::CaptureSettings::DEFAULT_EMAIL_PROMPT, admin_user: nil, typing: false
      ).once
      expect(Leads::RoutingService).not_to have_received(:route!)

      inbound("email", answer)
      2.times { described_class.perform_now(tenant.id, lead.id) }
      expect(lead.reload.email.presence).to eq(expected_email)
      expect(Leads::RoutingService).to have_received(:route!).with(lead).once
    end
  end

  it "não inicia captação para perfis sem configuração ativa" do
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: {"enabled" => false})
    lead = nil
    expect { lead = inbound("organic", "Olá") }.not_to have_enqueued_job(Instagram::CaptureJob)
    expect(lead).not_to be_instagram_capture_pending
  end
  it "inicia com os padrões para novos perfis sem configuração manual" do
    lead = nil
    expect { lead = inbound("default-organic", "Olá") }.to have_enqueued_job(described_class)
    expect(lead).to be_instagram_automation_holding
  end

  it "pausa assim que há corretor atribuído, mesmo sem resposta humana" do
    lead = inbound("first", "Oi")
    lead.update_columns(admin_user_id: integration.admin_user_id)
    described_class.perform_now(tenant.id, lead.id)
    expect(Instagram::Reply).not_to have_received(:with_typing)
    expect(Instagram::Reply).not_to have_received(:call)
    expect(Leads::RoutingService).not_to have_received(:route!)
  end

  it "permite uma resposta fixa antes do contato quando a condição autoriza" do
    settings.save_many(campaign_ids: ['default'], create_only: false, rule: {'enabled' => true, 'sdr_enabled' => true,
      'conditions' => [{'title' => 'Horário', 'match' => 'keywords', 'keywords' => 'horário', 'action' => 'fixed',
        'response' => 'Atendemos das 9h às 18h.', 'enabled' => true, 'ai_enabled' => false, 'require_contact' => false}]})
    lead = inbound('hours', 'Qual o horário de atendimento?')
    2.times { described_class.perform_now(tenant.id, lead.id) }
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: 'Atendemos das 9h às 18h.', admin_user: nil, typing: false).once
    expect(lead.reload).to be_instagram_capture_pending
    expect(Leads::RoutingService).not_to have_received(:route!)
  end

  it "a retenção do atendimento impede roteamento e contingência enquanto a IA atende" do
    lead = inbound('serving', 'Oi')
    lead.update_columns(client_name: 'Maria Silva', phone: '5547998887777',
      other_information: lead.other_information.deep_merge('instagram_capture' => {'step' => 'serving', 'sdr_cursor' => lead.instagram_messages.maximum(:id)}))
    expect(lead).to be_instagram_automation_holding
    expect(lead).to be_skip_automatic_routing
    expect(Leads::DistributorService).not_to receive(:distribute_to)
    Leads::RoutingService.route!(lead)
    expect(lead.reload.admin_user_id).to be_nil
  end

  it "retoma a dúvida após o site completar os dados sem nova mensagem e sem distribuição" do
    lead = inbound('first', 'Qual é o valor?')
    described_class.perform_now(tenant.id, lead.id)
    lead.update_columns(client_name: 'Maria Silva', phone: '5547998887777')
    catalog = instance_double(Instagram::CatalogReply, call: 'Valor cadastrado no imóvel.')
    allow(Instagram::CatalogReply).to receive(:new).and_return(catalog)
    2.times { described_class.perform_now(tenant.id, lead.id) }
    expect(lead.reload.other_information.dig('instagram_capture', 'step')).to eq('serving')
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: 'Valor cadastrado no imóvel.', admin_user: nil, typing: false).once
    expect(Leads::RoutingService).not_to have_received(:route!)
  end

  it "encaminha mesmo quando a Meta falha ao enviar o aviso" do
    lead = inbound('first', 'Quero um corretor')
    described_class.perform_now(tenant.id, lead.id)
    allow(Leads::RoutingService).to receive(:route!) { |record| record.update_columns(admin_user_id: integration.admin_user_id) }
    allow(Instagram::Reply).to receive(:call).with(hash_including(body: Instagram::CatalogReply::HANDOFF)).and_raise(Instagram::Reply::Error, 'Meta indisponível')
    inbound('contact', 'Maria Silva (47) 99888-7777')
    described_class.perform_now(tenant.id, lead.id)
    expect(Leads::RoutingService).to have_received(:route!).with(lead).once
    expect(lead.reload.admin_user_id).to eq(integration.admin_user_id)
  end

  it "continua atendendo se a distribuição ainda não encontrou corretor" do
    lead = inbound('first', 'Quero um corretor')
    described_class.perform_now(tenant.id, lead.id)
    allow(Leads::RoutingService).to receive(:route!)
    inbound('contact', 'Maria Silva (47) 99888-7777')
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload.other_information.dig('instagram_capture', 'step')).to eq('handoff_pending')
    expect(lead).to be_instagram_automation_active
    expect(lead).not_to be_instagram_automation_holding
    catalog = instance_double(Instagram::CatalogReply, call: 'Enquanto isso, posso ajudar a encontrar opções.')
    allow(Instagram::CatalogReply).to receive(:new).and_return(catalog)
    inbound('more', 'Quero ver outras opções')
    described_class.perform_now(tenant.id, lead.id)
    expect(catalog).to have_received(:call).once
    expect(Leads::RoutingService).to have_received(:route!).with(lead).once
  end

  it "encaminha compra confirmada à fila da página uma única vez, sem continuar a IA" do
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: {"enabled" => true, "sdr_enabled" => true})
    rule = create(:distribution_rule, tenant: tenant, business_type: :venda,
      source_site: false, source_meta: true, meta_page_ids: [page.page_id], auto_add_forms: true)
    agent = create(:admin_user, tenant: tenant)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent)
    allow(Leads::NotificationDispatcher).to receive(:push_to)
    lead = inbound("hello", "Oi")
    described_class.perform_now(tenant.id, lead.id)
    inbound("contact", "William (47) 99888-7777")
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload).to be_instagram_automation_holding
    expect(Instagram::CatalogReply).not_to receive(:new)
    inbound("intent", "Comprar")
    2.times { described_class.perform_now(tenant.id, lead.id) }
    expect(lead.reload).to have_attributes(admin_user_id: agent.id, distribution_rule_id: rule.id)
    expect(lead.other_information).to include("meta_page_id" => page.page_id, "business_type" => "venda")
    expect(lead).not_to be_instagram_automation_holding
    expect(lead.activities.where(kind: "distributed").count).to eq(1)
    expect(Leads::RoutingService).to have_received(:route!).with(lead).once
  end

  it "usa a intenção já informada antes dos dados e preserva o e-mail opcional" do
    settings.save(campaign_id: "default", enabled: true, name_prompt: "", phone_prompt: "", ask_email: true)
    lead = inbound("intent", "Quero alugar um apartamento")
    described_class.perform_now(tenant.id, lead.id)
    inbound("contact", "Maria Silva (47) 99888-7777")
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload.other_information.dig("instagram_capture", "step")).to eq("email")
    expect(Leads::RoutingService).not_to have_received(:route!)
    inbound("email", "Pular")
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload.other_information["business_type"]).to eq("locacao")
    expect(Leads::RoutingService).to have_received(:route!).with(lead).once
  end

  it "não encaminha intenção comercial sem confirmar o contato" do
    lead = inbound("intent", "Comprar")
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload.client_name).to be_blank
    expect(lead).to be_instagram_capture_pending
    expect(Leads::RoutingService).not_to have_received(:route!)
  end

  it "prepara o contexto de um contato antigo ao liberá-lo sem responder no Instagram" do
    lead = inbound("old", "Comprar")
    lead.update_columns(client_name: "William", phone: "5547998887777",
      other_information: {"instagram_capture" => {"step" => "serving", "sdr_cursor" => lead.instagram_messages.maximum(:id)}})
    described_class.release!(lead)
    expect(lead.reload.other_information).to include("meta_page_id" => page.page_id, "business_type" => "venda")
    expect(Leads::RoutingService).to have_received(:route!).with(lead).once
    expect(Instagram::Reply).not_to have_received(:call)
  end

  it "preserva a prioridade de resposta personalizada antes do encaminhamento comercial" do
    settings.save_many(campaign_ids: ['default'], create_only: false, rule: {'enabled' => true, 'sdr_enabled' => true,
      'conditions' => [
        {'title' => 'Compra', 'match' => 'keywords', 'keywords' => 'comprar', 'action' => 'fixed',
          'response' => 'Nossa equipe atende compras nesta região.', 'enabled' => true, 'ai_enabled' => false, 'require_contact' => true},
        {'title' => 'Busca', 'match' => 'always', 'action' => 'ai', 'enabled' => true, 'ai_enabled' => true, 'require_contact' => true}
      ]})
    lead = inbound('interest', 'Quero comprar')
    described_class.perform_now(tenant.id, lead.id)
    inbound('contact', 'Maria Silva (47) 99888-7777')
    described_class.perform_now(tenant.id, lead.id)
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: 'Nossa equipe atende compras nesta região.', admin_user: nil, typing: false)
    expect(Leads::RoutingService).not_to have_received(:route!)
  end

  it "mantém a exceção de IA antes da coleta sem encaminhar contato incompleto" do
    settings.save_many(campaign_ids: ['default'], create_only: false, rule: {'enabled' => true, 'sdr_enabled' => true,
      'conditions' => [{'title' => 'Busca aberta', 'match' => 'always', 'action' => 'ai',
        'enabled' => true, 'ai_enabled' => true, 'require_contact' => false}]})
    catalog = instance_double(Instagram::CatalogReply, call: 'Em qual cidade você procura?')
    allow(Instagram::CatalogReply).to receive(:new).and_return(catalog)
    lead = inbound('buy', 'Quero comprar')
    described_class.perform_now(tenant.id, lead.id)
    expect(catalog).to have_received(:call).once
    expect(Leads::RoutingService).not_to have_received(:route!)
    expect(lead.reload).to be_instagram_capture_pending
  end

end
