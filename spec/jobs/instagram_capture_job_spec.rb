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

  it "mantém o @ e responde sobre o imóvel sem exigir telefone, sem duplicar em retry" do
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: {"enabled" => true, "sdr_enabled" => true})
    catalog = instance_double(Instagram::CatalogReply, call: "O edifício informado no cadastro é Presidente Kennedy.")
    allow(Instagram::CatalogReply).to receive(:new).and_return(catalog)
    lead = inbound("question", "Qual nome desse edifício?")
    lead.update_columns(other_information: lead.other_information.deep_merge("instagram_profile" => {"username" => "ednadgazevedo"}))
    2.times { described_class.perform_now(tenant.id, lead.id) }
    expect(lead.reload.client_name).to be_blank
    expect(lead.phone).to be_blank
    expect(lead.display_name).to eq("@ednadgazevedo")
    expect(catalog).to have_received(:call).once
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: "O edifício informado no cadastro é Presidente Kennedy.", admin_user: nil, typing: false).once
    expect(Leads::RoutingService).not_to have_received(:route!)
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

  it "continua pelo Instagram quando a pessoa prefere não informar telefone" do
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: {"enabled" => true, "sdr_enabled" => true})
    catalog = instance_double(Instagram::CatalogReply, call: "Podemos continuar por aqui. Você procura venda ou locação?")
    allow(Instagram::CatalogReply).to receive(:new).and_return(catalog)
    lead = inbound("first", "Prefiro continuar por aqui")
    2.times { described_class.perform_now(tenant.id, lead.id) }
    expect(lead.reload.phone).to be_blank
    expect(Leads::RoutingService).not_to have_received(:route!)
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: "Podemos continuar por aqui. Você procura venda ou locação?", admin_user: nil, typing: false).once
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

  it "responde primeiro e não repete a dúvida depois de receber o contato voluntário" do
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: {"enabled" => true, "sdr_enabled" => true})
    catalog = instance_double(Instagram::CatalogReply, call: "O imóvel aceita financiamento.")
    allow(Instagram::CatalogReply).to receive(:new).and_return(catalog)
    lead = inbound("question", "Como é a forma de pagamento?")
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload.phone).to be_blank
    inbound("contact", "Edna (47) 99888-7777")
    2.times { described_class.perform_now(tenant.id, lead.id) }
    expect(lead.reload).not_to be_instagram_capture_pending
    expect(Leads::RoutingService).not_to have_received(:route!)
    expect(catalog).to have_received(:call).once
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: "O imóvel aceita financiamento.", admin_user: nil, typing: false).once
  end

  it "registra encaminhamento e avisa o corretor uma única vez quando faltam informações" do
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: {"enabled" => true, "sdr_enabled" => true})
    lead = inbound("first", "Oi")
    described_class.perform_now(tenant.id, lead.id)
    catalog = instance_double(Instagram::CatalogReply, call: Instagram::CatalogReply::HANDOFF)
    allow(Instagram::CatalogReply).to receive(:new).and_return(catalog)
    allow(Leads::RoutingService).to receive(:route!) { |record| record.update_columns(admin_user_id: integration.admin_user_id) }
    allow(Leads::NotificationDispatcher).to receive(:push_to)
    inbound("contact", "Edna (47) 99888-7777")
    inbound("question", "Como é a forma de pagamento?")
    2.times { described_class.perform_now(tenant.id, lead.id) }
    expect(lead.reload.other_information.dig('instagram_capture', 'sdr_cursor')).to be_nil
    expect(lead.activities.where(kind: 'note').where("metadata ? 'instagram_handoff_cursor'").count).to eq(1)
    expect(Leads::NotificationDispatcher).to have_received(:push_to).with(integration.admin_user, hash_including(event: 'instagram_handoff')).once
    expect(Leads::RoutingService).to have_received(:route!).with(lead).once
  end

  it "também responde ao contato antigo sem reiniciar uma cobrança de dados" do
    lead = inbound("old-contact", "Oi")
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: {"enabled" => true, "sdr_enabled" => true})
    catalog = instance_double(Instagram::CatalogReply, call: "Forma de pagamento cadastrada.")
    allow(Instagram::CatalogReply).to receive(:new).and_return(catalog)
    inbound("question", "Como é a forma de pagamento?")
    described_class.perform_now(tenant.id, lead.id)
    expect(catalog).to have_received(:call).once
    expect(lead.reload.phone).to be_blank
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
    expect(catalog).to receive(:call).with(array_including(hash_including(role: "cliente", text: "Quero um apartamento")), first_turn: true).once.and_return("Em qual bairro?")
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
      hash_including(role: "cliente", text: "Busco uma casa em Itajaí"),
      hash_including(role: "assistente", text: "Qual bairro?"),
      hash_including(role: "cliente", text: "Centro")
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

  it "não repete a consulta quando o site completa os dados sem nova mensagem" do
    catalog = instance_double(Instagram::CatalogReply, call: 'Valor cadastrado no imóvel.')
    allow(Instagram::CatalogReply).to receive(:new).and_return(catalog)
    lead = inbound('first', 'Qual é o valor?')
    described_class.perform_now(tenant.id, lead.id)
    lead.update_columns(client_name: 'Maria Silva', phone: '5547998887777')
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

  it "aguarda a equipe sem reiniciar o SDR quando a distribuição não encontrou corretor" do
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
    expect(catalog).not_to have_received(:call)
    expect(Leads::RoutingService).to have_received(:route!).with(lead).once
  end

  it "encaminha compra confirmada à fila da página uma única vez, sem continuar a IA" do
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: {"enabled" => true, "sdr_enabled" => true})
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: {"enabled" => true, "sdr_enabled" => true,
      "conditions" => [{"title" => "Compra para equipe", "match" => "keywords", "keywords" => "comprar", "action" => "handoff", "enabled" => true, "require_contact" => true}]})
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

  it "não pede contato nem responde comercialmente a menção, reação ou compartilhamento sem pedido" do
    settings.save_many(campaign_ids: ["default"], create_only: false, rule: {"enabled" => true, "sdr_enabled" => true})
    lead = inbound("mention", "")
    message = lead.instagram_messages.inbound.sole
    message.update!(context: {"attachments" => [{"type" => "story_mention", "url" => "https://example.com/story"}]})
    ["", "😍", "Compartilhando nossa publicação, obrigado pelo apoio"].each do |body|
      message.update!(body: body)
      described_class.perform_now(tenant.id, lead.id)
    end
    expect(Instagram::Reply).not_to have_received(:call)
    expect(Leads::RoutingService).not_to have_received(:route!)
    expect(lead.reload).to be_instagram_capture_pending
    message.update!(body: "Qual o valor desse imóvel?")
    described_class.perform_now(tenant.id, lead.id)
    expect(Instagram::Reply).to have_received(:call)
  end

  it "inclui o contexto no histórico sem confundir legenda com texto do cliente" do
    lead = inbound("mention", "")
    lead.instagram_messages.inbound.sole.update!(context: {"attachments" => [{"type" => "ig_post", "title" => "Casa compartilhada"}]})
    history = described_class.new.send(:conversation_history, lead, lead.instagram_messages.maximum(:id))
    expect(history).to contain_exactly(hash_including(role: "cliente", text: "Compartilhou uma publicação: Casa compartilhada", message_id: lead.instagram_messages.inbound.sole.id))
  end

  it "encaminha uma única vez mesmo sem telefone, sem reiniciar o SDR na próxima mensagem" do
    settings.save_many(campaign_ids: ['default'], create_only: false, rule: {'enabled' => true, 'sdr_enabled' => true})
    catalog = instance_double(Instagram::CatalogReply, call: Instagram::CatalogReply::HANDOFF)
    allow(Instagram::CatalogReply).to receive(:new).and_return(catalog)
    lead = inbound('question', 'Qual é a entrada?')
    2.times { described_class.perform_now(tenant.id, lead.id) }
    inbound('ack', 'Ok')
    described_class.perform_now(tenant.id, lead.id)
    inbound('follow-up', 'Já mandei o código do apartamento')
    described_class.perform_now(tenant.id, lead.id)
    expect(catalog).to have_received(:call).once
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: Instagram::CatalogReply::HANDOFF, admin_user: nil, typing: false).once
    expect(lead.reload.other_information.dig('instagram_capture', 'step')).to eq('handoff_pending')
    expect(lead.activities.where(kind: 'note').where("metadata ? 'instagram_handoff_cursor'").count).to eq(1)
    expect(Leads::RoutingService).not_to have_received(:route!)
  end

  it "responde o edifício do reel pelo catálogo atual antes de pedir nome e telefone" do
    settings.save_many(campaign_ids: ['default'], create_only: false, rule: {'enabled' => true, 'sdr_enabled' => true})
    create(:habitation, tenant: tenant, codigo: '9705', nome_empreendimento: 'Presidente Kennedy')
    provider = instance_double(Ai::Provider, api_key: 'test-only', resolved_model: 'test-model')
    client = instance_double(OpenAi::Client)
    allow(Ai::Provider).to receive(:active).with(tenant: tenant).and_return(provider)
    allow(Ai::Provider).to receive(:build_client).with(tenant: tenant).and_return(client)
    allow(client).to receive(:create_response) do |payload|
      expect(JSON.parse(payload[:input])['registered_facts']['building']).to eq('Edifício: Presidente Kennedy.')
      {'output_text' => {facts: ['building'], needs_broker: false}.to_json}
    end
    InstagramDirectJob.perform_now('12345', {'sender' => {'id' => '98765'}, 'recipient' => {'id' => '12345'},
      'message' => {'mid' => 'reel-context', 'attachments' => [{'type' => 'ig_reel', 'payload' => {'title' => ('Descrição do imóvel. ' * 40) + 'Cód. 9705'}}]}})
    lead = inbound('building-question', 'Bom dia tudo bom? Qual nome desse edifício por gentileza')
    2.times { described_class.perform_now(tenant.id, lead.id) }
    expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: a_string_including('Presidente Kennedy'), admin_user: nil, typing: false).once
    expect(lead.reload.phone).to be_blank
    expect(lead.client_name).to be_blank
    expect(Leads::RoutingService).not_to have_received(:route!)
  end

end
