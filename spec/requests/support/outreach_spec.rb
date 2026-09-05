require 'rails_helper'
RSpec.describe 'Contato ativo recebido',type: :request do
  let(:tenant) { Tenant.create!(name:'Outreach QA',slug:"outreach-#{SecureRandom.hex(5)}") }
  let(:user) { create(:admin_user,tenant:tenant,active:true) }
  let(:account) { Support::Account.create!(uid:SecureRandom.uuid,local_tenant_id:tenant.id,name:tenant.name,endpoint:'https://admin.unitymob.com.br',secret:'s'*64) }
  def signed_post(path,payload)
    body=payload.to_json; timestamp=Time.current.to_i.to_s
    post path,params:body,headers:{'CONTENT_TYPE'=>'application/json','X-Support-Account'=>account.uid,'X-Support-Timestamp'=>timestamp,'X-Support-Signature'=>Support::Transport.signature(account.secret,timestamp,body)}
  end
  it 'limita diretório à conta e cria a projeção uma única vez, com aviso ao usuário' do
    host! 'localhost'
    signed_post('/internal/support/v1/recipients',{id:user.id})
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['users'].map { |u| u['id'] }).to eq([user.id.to_s])
    ticket_uid=SecureRandom.uuid; message_uid=SecureRandom.uuid
    payload={'event_id'=>SecureRandom.uuid,'kind'=>'outreach','ticket'=>{'uid'=>ticket_uid,'requester_id'=>user.id.to_s,'requester_name'=>user.name,'subject'=>'Contato ativo','origin'=>'ativo','status'=>'aguardando_usuario','revision'=>1,'intake'=>Support::Ticket::QUESTIONS.keys.index_with{'Suporte iniciou contato'}},'message'=>{'uid'=>message_uid,'side'=>'support','author'=>'Equipe','body'=>'Vamos ajudar','revision'=>0,'files'=>[]}}
    2.times {signed_post('/internal/support/v1/events',payload);expect(response).to have_http_status(:ok)}
    ticket=account.tickets.find_by!(uid:ticket_uid)
    expect(ticket.messages.count).to eq(1)
    expect(ticket.messages.first.notification_pending).to eq(true)
    revised=payload.deep_dup; revised['kind']='snapshot';revised['event_id']=SecureRandom.uuid;revised['ticket']['revision']=2;revised['message'].merge!('revision'=>1,'body'=>'Texto editado','edited_at'=>Time.current.iso8601)
    signed_post('/internal/support/v1/events',revised)
    expect(ticket.messages.first.reload.body).to eq('Texto editado')
    stale=payload.merge('event_id'=>SecureRandom.uuid,'kind'=>'snapshot')
    signed_post('/internal/support/v1/events',stale)
    expect(ticket.messages.first.reload.body).to eq('Texto editado')
    bad=payload.deep_dup;bad['event_id']=SecureRandom.uuid;bad['ticket']['uid']=SecureRandom.uuid;bad['ticket']['requester_id']='-1'
    signed_post('/internal/support/v1/events',bad)
    expect(response).to have_http_status(:not_found)
  end
end
