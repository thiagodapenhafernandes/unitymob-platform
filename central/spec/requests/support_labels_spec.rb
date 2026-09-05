require 'rails_helper'
RSpec.describe 'Catálogo de etiquetas',type: :request do
  it 'cria cor, aplica, renomeia, remove e preserva auditoria e entrega' do
    central_login
    ticket=support_ticket
    post '/support_labels',params:{ticket_id:ticket.id,label:{name:'Urgente',color:'#ff0000',description:'Priorizar'}},as: :json
    expect(response).to have_http_status(:ok)
    label=SupportLabel.find_by!(name:'Urgente')
    2.times { post "/support_labels/#{label.id}/apply",params:{ticket_id:ticket.id,applied:true},as: :json }
    expect(ticket.reload.labels).to eq('Urgente')
    expect(response.parsed_body['labels'].first['applied']).to eq(true)
    patch "/support_labels/#{label.id}",params:{ticket_id:ticket.id,label:{name:'Prioritário',color:'#ffff00'}},as: :json
    expect(ticket.reload.labels).to eq('Prioritário')
    expect(response.parsed_body['labels'].first['text_color']).to eq('#0f172a')
    expect(ticket.deliveries.count).to eq(2)
    expect(Support::Audit.where(ticket_id:ticket.id).count).to eq(2)
    delete "/support_labels/#{label.id}",params:{ticket_id:ticket.id},as: :json
    expect(ticket.reload.labels).to eq('')
    expect(SupportLabel.exists?(label.id)).to eq(false)
  end
  it 'bloqueia financeiro, cor inválida, duplicatas e aplicação em encerrado' do
    ticket=support_ticket
    central_login('financeiro')
    get '/support_labels',params:{ticket_id:ticket.id},as: :json
    expect(response).to have_http_status(:forbidden)
    central_login('admin')
    post '/support_labels',params:{ticket_id:ticket.id,label:{name:'Cor',color:'red;display:none'}},as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    label=SupportLabel.create!(name:'Bug',color:'#123456')
    post '/support_labels',params:{ticket_id:ticket.id,label:{name:'BUG',color:'#123456'}},as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    ticket.update!(status:'resolvido',resolved_at:Time.current)
    post "/support_labels/#{label.id}/apply",params:{ticket_id:ticket.id,applied:true},as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ticket.reload.labels).to be_blank
  end
end
