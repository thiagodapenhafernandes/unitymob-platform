require 'rails_helper'

RSpec.describe 'Notificações de leads arquivados' do
  let(:owner) { create(:admin_user, :admin) }
  let(:tenant) { owner.tenant }
  let(:lead) { create(:lead, tenant: tenant, admin_user: owner) }

  it 'revalida o banco mesmo quando o objeto ainda não sabe do arquivamento' do
    expect(lead.notifications_allowed?).to be(true)
    tenant.leads.where(id: lead.id).update_all(archived_at: Time.current)
    expect(lead.archived_at).to be_nil
    expect(lead.notifications_allowed?).to be(false)
    tenant.leads.where(id: lead.id).update_all(archived_at: nil)
    expect(lead.notifications_allowed?).to be(true)
  end

  it 'bloqueia todos os canais da distribuição e eventos extras antes de enfileirar' do
    rule = create(:distribution_rule, tenant: tenant, notify_push: true, notify_whatsapp: true, notify_email: true, notify_webhook: true)
    lead.update_columns(distribution_rule_id: rule.id, archived_at: Time.current)
    expect(Notifications::PushDispatcher).not_to receive(:deliver)
    expect(Notifications::PushDeliveryJob).not_to receive(:perform_later)
    expect(Notifications::TransportResolver).not_to receive(:whatsapp)
    expect(Notifications::TransportResolver).not_to receive(:email)
    expect(Leads::WebhookDeliveryJob).not_to receive(:perform_later)
    expect do
      Leads::NotificationDispatcher.deliver(lead)
      Leads::NotificationDispatcher.push_to(owner, title: 'Interesse', body: 'Nova consulta', url: '/admin/leads', lead: lead, event: 'lead_interest')
    end.not_to change(InAppNotification, :count)
  end

  it 'bloqueia sino e push, inclusive jobs antigos identificados pela URL' do
    lead.update_columns(archived_at: Time.current)
    expect do
      InAppNotification.notify!(admin_user: owner, kind: 'lead_event', title: 'Aviso', metadata: {lead_id: lead.id})
    end.not_to change(InAppNotification, :count)
    expect(WebPush).not_to receive(:payload_send)
    expect(Notifications::PushDispatcher.deliver(admin_user_id: owner.id, title: 'Agendamento', body: 'Visita', lead_id: lead.id)).to eq(0)
    Notifications::PushDeliveryJob.perform_now(admin_user_id: owner.id, title: 'Aviso antigo', body: 'Retorno', url: "/admin/leads/#{lead.id}/attend")
    Notifications::PushDeliveryJob.perform_now(admin_user_id: owner.id, title: "Aviso com link seguro", body: "Contato", url: "/s/token", lead_id: lead.id)
    expect(PushDeliveryEvent.where(lead_id: lead.id)).not_to exist
  end

  [:task, :appointment].each do |kind|
    it "bloqueia lembrete de #{kind} arquivado depois de carregar a atividade" do
      activity = create(kind, tenant: tenant, lead: lead, admin_user: owner, (kind == :task ? :due_at : :starts_at) => 1.minute.ago)
      activity.lead
      tenant.leads.where(id: lead.id).update_all(archived_at: Time.current)
      expect do
        Activities::ReminderDelivery.new(activity, setting: LeadSetting.instance(tenant: tenant), now: Time.current).call { raise 'não deveria enviar' }
      end.not_to change { activity.reload.reminder_state }
    end
  end

  it 'descarta webhook enfileirado antes de arquivar e mensagens automáticas de regras' do
    payload = {'lead' => {'id' => lead.id, 'tenant_id' => tenant.id}, 'corretor' => {'id' => owner.id}}
    lead.update_columns(archived_at: Time.current)
    expect(WebhookService).not_to receive(:send_form_data)
    Leads::WebhookDeliveryJob.perform_now('https://example.com/webhook', payload)
    expect(Whatsapp::SendMessageJob).not_to receive(:dispatch)
    Automation::ActionExecutor.execute({type: 'send_whatsapp', message: 'Olá'}, lead)
  end

  it 'não monta nem entrega e-mail após arquivar, mesmo com e-mail já preparado' do
    Rails.application.routes.default_url_options[:host] = 'localhost'
    mail = LeadMailer.with(lead: lead).lead_assigned
    mail.message
    tenant.leads.where(id: lead.id).update_all(archived_at: Time.current)
    expect { mail.deliver_now }.not_to change(ActionMailer::Base.deliveries, :size)
    expect(LeadMailer.with(lead: lead).new_lead_notification.message).to be_a(ActionMailer::Base::NullMail)
  end
  it 'cancela WhatsApp automático que já estava pendente antes de arquivar' do
    conversation = tenant.whatsapp_conversations.create!(contact_phone: '5547998887777', lead: lead)
    message = conversation.messages.create!(direction: 'outbound', status: 'pending', msg_type: 'text', body: 'Lembrete')
    lead.update_columns(archived_at: Time.current)
    expect(Whatsapp::CloudClient).not_to receive(:new)
    Whatsapp::SendMessageJob.perform_now(message.id, tenant_id: tenant.id)
    expect(message.reload).to have_attributes(status: 'failed', error_message: 'Lead arquivado: envio automático cancelado.')
  end

  it 'mantém a comunicação manual do corretor disponível' do
    conversation = tenant.whatsapp_conversations.create!(contact_phone: '5547998887777', lead: lead)
    message = conversation.messages.create!(direction: 'outbound', status: 'pending', msg_type: 'text', body: 'Resposta manual', admin_user: owner)
    lead.update_columns(archived_at: Time.current)
    client = instance_double(Whatsapp::CloudClient, send_text: {ok: true, message_id: 'manual-test'})
    allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
    Whatsapp::SendMessageJob.perform_now(message.id, tenant_id: tenant.id)
    expect(message.reload.status).to eq('sent')
  end

  it 'descarta webhook de automação que ficou na fila antes do arquivamento' do
    delivery = AutomationWebhookDelivery.create!(lead: lead, url: 'http://93.184.216.34/hook', http_method: 'post')
    lead.update_columns(archived_at: Time.current)
    expect(Automation::WebhookDeliveryService).not_to receive(:call)
    Automation::WebhookDeliveryJob.perform_now(delivery.id)
  end

end
