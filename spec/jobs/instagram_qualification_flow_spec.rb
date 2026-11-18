require 'rails_helper'

RSpec.describe 'Qualificação e encaminhamento do Instagram' do
  include ActiveJob::TestHelper
  let(:tenant) { Tenant.default }
  let(:meta) { create(:user_meta_integration, tenant: tenant) }
  let!(:page) { create(:meta_facebook_page, user_meta_integration: meta, instagram_id: '12345', instagram_enabled: true) }
  let(:agent) do
    profile = tenant.profiles.create!(name: 'Atendimento Instagram', axis: 'vertical', position: 700,
      permissions: {'leads' => {'view' => true, 'edit' => true, 'scope' => 'own'}})
    create(:admin_user, :field_agent, tenant: tenant, profile: profile)
  end
  let(:settings) { Instagram::CaptureSettings.new(page, tenant: tenant) }

  before do
    clear_enqueued_jobs
    meta.update!(selected_page_ids: [page.page_id])
    settings.save_many(campaign_ids: ['default'], create_only: false, rule: {'enabled' => true, 'sdr_enabled' => true})
    allow(Instagram::Reply).to receive(:with_typing).and_wrap_original { |_method, *_args, &block| block.call }
    allow(Instagram::Reply).to receive(:call) { Struct.new(:occurred_at).new(Time.current) }
    allow(Leads::NotificationDispatcher).to receive(:deliver)
    allow(Leads::NotificationDispatcher).to receive(:push_to)
    allow(Instagram::CatalogReply).to receive(:new).and_return(instance_double(Instagram::CatalogReply, call: 'Encontrei opções ativas compatíveis com sua busca.'))
  end

  def receive_message(mid, text, run_capture: true, attachments: nil)
    InstagramDirectJob.perform_now('12345', {'sender' => {'id' => '98765'}, 'recipient' => {'id' => '12345'},
      'message' => {'mid' => mid, 'text' => text, 'attachments' => attachments}})
    lead = tenant.leads.find_by!(instagram_scoped_id: '98765')
    Instagram::CaptureJob.perform_now(tenant.id, lead.id) if run_capture
    lead.reload
  end

  def rule(destination: 'unitymob', **attributes)
    create(:distribution_rule, tenant: tenant, source_site: false, source_meta: true, meta_page_ids: [page.page_id],
      delivery_destination: destination, **attributes)
  end

  it 'encaminha locação fragmentada para a fila interna somente após contato completo, uma vez' do
    queue = rule(business_type: :locacao, custom_filters: [
      {'key' => 'origin', 'value' => 'Instagram Direct'}, {'key' => 'instagram_qualified', 'value' => 'true'}])
    create(:distribution_rule_agent, distribution_rule: queue, admin_user: agent)
    lead = receive_message('rent', 'Aluguel?')
    Instagram::SearchContext.new(lead).remember!('city' => ['Barra Sul - Balneário Camboriú'])
    receive_message('type', 'Apartamento')
    receive_message('budget', 'Até uns 12')
    receive_message('fees', 'C taxas')
    lead.instagram_messages.create!(direction: 'outbound', message_id: 'question', body: 'Quantos quartos?', occurred_at: Time.current)
    receive_message('rooms', '3')
    lead = receive_message('annual', 'Anual')
    expect(lead.client_name).to be_blank
    expect(lead.other_information.dig('instagram_qualification', 'ready')).to be(true)
    expect(lead.admin_user_id).to be_nil
    receive_message('name', 'Me chamo Maria')
    lead = receive_message('phone', 'Meu WhatsApp é (47) 99888-7777')
    expect(lead).to have_attributes(admin_user_id: agent.id, distribution_rule_id: queue.id)
    expect(lead.business_label).to eq('Locação')
    expect(Leads::NotificationDispatcher).to have_received(:deliver).once
    Instagram::CaptureJob.perform_now(tenant.id, lead.id)
    expect(Leads::NotificationDispatcher).to have_received(:deliver).once
  end

  it 'Conexão: responde antes do contato, qualifica e distribui uma vez na fila configurada' do
    queue = rule(business_type: :venda, pocket_active: true, pocket_time: 5)
    property = create(:habitation, tenant: tenant, titulo_anuncio: 'Opção ativa Centro', categoria: 'Apartamento', status: 'Venda', dormitorios_qtd: 2, valor_venda_cents: 85_000_000)
    allow(Instagram::CatalogReply).to receive(:new).and_call_original
    query = instance_double(Ai::PropertySearch::PublicQuery, call: Ai::PropertySearch::PublicQuery::Result.new({}, nil, nil))
    allow(Ai::PropertySearch::PublicQuery).to receive(:new).and_return(query)
    allow(Storage::PublicCdnImageUrl).to receive(:resolve).and_return('https://example.test/property.jpg')
    create(:distribution_rule_agent, distribution_rule: queue, admin_user: agent)
    lead = receive_message('search', 'Procuro comprar apartamento de 2 quartos no Centro até 900 mil')
    expect(lead.admin_user_id).to be_nil
    expect(Instagram::Reply).to have_received(:call).with(hash_including(body: include(property.titulo_anuncio)))
    expect(lead.other_information.dig('instagram_qualification', 'ready')).to be(true)
    receive_message('name', 'Me chamo Maria')
    lead = receive_message('phone', 'Meu WhatsApp é (47) 99888-7777')
    expect(lead).to have_attributes(admin_user_id: agent.id, distribution_rule_id: queue.id)
    expect(lead.business_label).to eq('Venda')
    expect(lead.activities.where(kind: 'note').pluck(:metadata).to_s).to include('2 quartos', 'Centro', 'Venda')
    expect(Leads::NotificationDispatcher).to have_received(:deliver).once
    receive_message('return', 'Pode ser amanhã às 15h?')
    expect(Leads::NotificationDispatcher).to have_received(:deliver).once
    expect(lead.reload.admin_user_id).to eq(agent.id)
    notice = InAppNotification.where(admin_user: agent, kind: 'instagram_message').recent.first
    expect(notice.metadata['lead_id']).to eq(lead.id)
    expect(notice.broadcast_payload[:lead_id]).to eq(lead.id)
    expect(Notifications::PushDeliveryJob).to have_been_enqueued.with(hash_including(admin_user_id: agent.id, lead_id: lead.id))
  end

  it 'Salute com destino Instagram habilitado: entrega qualificação e modalidade ao C2S, sem exportar antes nem duplicar no retry' do
    integration = create(:external_lead_integration, tenant: tenant, export_enabled: true)
    queue = rule(destination: 'c2s', custom_filters: [{'key' => 'origin', 'value' => 'Instagram Direct'},
      {'key' => 'instagram_qualified', 'value' => 'true'}])
    api = instance_double(ExternalLeadMigration::Client)
    allow(ExternalLeadMigration::Client).to receive(:new).with(token: integration.access_token).and_return(api)
    allow(api).to receive(:create_lead).and_return('lead_id' => 'remote-123')
    property = create(:habitation, tenant: tenant, codigo: '9705', status: 'Venda')
    lead = receive_message('share', '', attachments: [{'type' => 'ig_post', 'payload' => {'title' => "Cód. #{property.codigo}"}}])
    ExternalLeadMigration::ExportLeadJob.perform_now(lead.id, tenant_id: tenant.id)
    expect(api).not_to have_received(:create_lead)
    receive_message('intent', 'Quero visitar esse apartamento')
    receive_message('name', 'Me chamo Maria')
    lead = receive_message('phone', 'Meu WhatsApp é (47) 99888-7777')
    expect(lead).to have_attributes(distribution_rule_id: queue.id, property_id: property.id, admin_user_id: nil)
    2.times { ExternalLeadMigration::ExportLeadJob.perform_now(lead.id, tenant_id: tenant.id) }
    expect(api).to have_received(:create_lead).with(hash_including('data' => hash_including('attributes' => hash_including(
      'type_negotiation' => 'Comprar', 'prop_ref' => '9705', 'observation' => include('Quero visitar', 'Venda')))), path: integration.export_endpoint_path).once
    expect(lead.reload.c2s_export_external_id).to eq('remote-123')
  end

  it 'reconcilia o provisório com lead existente, mantém corretor e histórico e não gira a fila' do
    queue = rule
    create(:distribution_rule_agent, distribution_rule: queue, admin_user: agent)
    existing = create(:lead, tenant: tenant, name: 'Maria antiga', phone: '47998887777', origin: 'Site',
      admin_user: agent, skip_automatic_routing: true)
    existing.activities.create!(kind: 'note', metadata: {'body' => 'Histórico anterior'})
    provisional = receive_message('question', 'Qual é o valor?', run_capture: false)
    provisional.activities.create!(kind: 'note', metadata: {'body' => 'Contexto provisório'})
    count = tenant.leads.count
    lead = receive_message('contact', 'Meu WhatsApp é (47) 99888-7777')
    expect(lead.id).to eq(existing.id)
    expect(tenant.leads.count).to eq(count - 1)
    expect(Lead.exists?(provisional.id)).to be(false)
    expect(lead).to have_attributes(origin: 'Site', admin_user_id: agent.id, name: 'Maria antiga')
    expect(lead.instagram_messages.pluck(:message_id)).to match_array(%w[question contact])
    expect(lead.activities.pluck(:metadata).to_s).to include('Histórico anterior', 'Contexto provisório')
    expect(Leads::NotificationDispatcher).not_to have_received(:deliver)
    expect(Instagram::Reply).not_to have_received(:call)
    expect(InAppNotification.where(admin_user: agent, kind: 'instagram_message').recent.first.metadata['lead_id']).to eq(existing.id)
  end

  it 'anexa atualização ao mesmo lead C2S, preservando proprietário remoto e sem novo POST' do
    integration = create(:external_lead_integration, tenant: tenant, export_enabled: false, operational_mappings: {'mirror_c2s_owners' => true})
    existing = create(:lead, tenant: tenant, name: 'Maria', client_name: 'Maria', phone: '47998887777', origin: 'Site',
      admin_user: agent, external_lead_integration: integration, external_lead_id: 'imported-9', skip_automatic_routing: true)
    api = instance_double(ExternalLeadMigration::Client)
    allow(ExternalLeadMigration::Client).to receive(:new).and_return(api)
    allow(api).to receive(:update_lead_routing).and_return('success' => true)
    expect(api).not_to receive(:create_lead)
    receive_message('contact', 'Meu WhatsApp é (47) 99888-7777')
    lead = receive_message('intent', 'Procuro alugar apartamento de 2 quartos no Centro até 4 mil')
    2.times { ExternalLeadMigration::SyncInstagramQualificationJob.perform_now(tenant.id, lead.id) }
    expect(api).to have_received(:update_lead_routing).with('imported-9', attributes: {
      'body' => include('Locação', 'Centro', '2 quartos'), 'type_negotiation' => 1}).once
    expect(lead.reload.admin_user_id).to eq(existing.admin_user_id)
    expect(Instagram::Reply).not_to have_received(:call)
  end
  it 'respeita a recusa de telefone e deixa encaminhamento manual sem exportação ou insistência' do
    create(:external_lead_integration, tenant: tenant, export_enabled: true)
    receive_message('search', 'Procuro alugar apartamento de 2 quartos no Centro até 4 mil')
    lead = receive_message('refusal', 'Prefiro continuar por aqui sem telefone')
    expect(lead.other_information.dig('instagram_capture', 'step')).to eq('handoff_pending')
    receive_message('repeat', 'Podemos continuar por aqui')
    expect(Instagram::Reply).to have_received(:call).with(hash_including(body: Instagram::CatalogReply::HANDOFF)).once
    expect(ExternalLeadMigration::ExportLeadJob).not_to have_been_enqueued
  end

  %w[comprar alugar].each do |business|
    it "preserva configuração atual da Salute: regra WhatsApp não recebe Instagram para #{business}" do
      create(:external_lead_integration, tenant: tenant, export_enabled: false, operational_mappings: {'mirror_c2s_owners' => true})
      create(:distribution_rule, tenant: tenant, delivery_destination: 'c2s', business_type: :locacao,
        source_site: false, source_meta: false, source_whatsapp_campaign: true, c2s_negotiation_type: 'Aluguel')
      receive_message('search', "Procuro #{business} apartamento de 2 quartos no Centro")
      receive_message('name', 'Me chamo Maria')
      lead = receive_message('phone', 'Meu WhatsApp é (47) 99888-7777')
      expect(lead.distribution_rule_id).to be_nil
      expect(lead.other_information.dig('instagram_capture', 'step')).to eq('handoff_pending')
      expect(ExternalLeadMigration::ExportLeadJob).not_to have_been_enqueued
    end
  end

  it 'preserva exportação global após coletar contato no fluxo sem SDR' do
    create(:external_lead_integration, tenant: tenant, export_enabled: true)
    settings.save_many(campaign_ids: ['default'], create_only: false, rule: {'enabled' => true, 'sdr_enabled' => false})
    lead = receive_message('hi', 'Oi')
    expect(ExternalLeadMigration::ExportLeadJob).not_to have_been_enqueued
    receive_message('name', 'Me chamo Maria')
    receive_message('phone', 'Meu WhatsApp é (47) 99888-7777')
    expect(ExternalLeadMigration::ExportLeadJob).to have_been_enqueued.with(lead.id, tenant_id: tenant.id).once
  end

  %w[venda locacao].each do |business|
    it "Salute: só exporta Instagram #{business} após concluir qualificação e contato" do
      integration = create(:external_lead_integration, tenant: tenant, export_enabled: false)
      queue = rule(destination: 'c2s', business_type: business,
        c2s_negotiation_type: business == 'venda' ? 'Compra' : 'Aluguel',
        custom_filters: [{'key' => 'origin', 'value' => 'Instagram Direct'}, {'key' => 'instagram_qualified', 'value' => 'true'}])
      api = instance_double(ExternalLeadMigration::Client, create_lead: {'lead_id' => "#{business}-remote"})
      allow(ExternalLeadMigration::Client).to receive(:new).and_return(api)
      verb = business == 'venda' ? 'comprar' : 'alugar'
      lead = receive_message('search', "Procuro #{verb} apartamento de 2 quartos no Centro")
      expect(lead).not_to be_instagram_qualified_for_delivery
      expect(Leads::DistributorService.new(lead).matching_entry_rule).to be_nil
      receive_message('name', 'Me chamo Maria')
      expect(ExternalLeadMigration::ExportLeadJob).not_to have_been_enqueued
      lead = receive_message('phone', 'Meu WhatsApp é (47) 99888-7777')
      expect(lead).to be_instagram_qualified_for_delivery
      expect(lead.distribution_rule_id).to eq(queue.id)
      ExternalLeadMigration::ExportLeadJob.perform_now(lead.id, tenant_id: tenant.id)
      expect(api).to have_received(:create_lead).with(hash_including('data' => hash_including('attributes' => hash_including(
        'type_negotiation' => business == 'venda' ? 'Comprar' : 'Alugar',
        'observation' => include('2 quartos', 'Centro')))), path: integration.export_endpoint_path).once
      other_source = build(:lead, tenant: tenant, origin: 'Facebook Lead Ads', other_information: lead.other_information)
      expect(Leads::DistributorService.new(other_source).matching_entry_rule).to be_nil
      lead.update_columns(client_phone: nil, phone: nil)
      expect(lead.reload).not_to be_instagram_qualified_for_delivery
    end
  end

end
