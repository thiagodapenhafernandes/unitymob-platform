require 'rails_helper'
RSpec.describe 'Login com código por e-mail', type: :request do
  let!(:staff) { Staff.create!(name: 'Contato', email: 'contato@example.test', role: 'admin', password: 'senha-para-teste-123', activated_at: Time.current, verification_method: 'email') }
  before { ActionMailer::Base.deliveries.clear }
  def request_code
    post '/login', params: { email: staff.email, password: 'senha-para-teste-123' }
    expect(response).to redirect_to('/login/verify')
    ActionMailer::Base.deliveries.last.body.decoded[/\d{6}/]
  end
  it 'envia código ao e-mail cadastrado e só cria sessão após verificá-lo' do
    code = request_code
    expect(ActionMailer::Base.deliveries.last.to).to eq([staff.email])
    expect(response.body).not_to include(code)
    get '/'
    expect(response).to redirect_to('/login')
    get '/login/verify'
    expect(response).to have_http_status(:ok)
    post '/login/verify', params: { code: code }
    expect(response).to redirect_to('/')
    expect(staff.reload.email_code_digest).to be_nil
    get '/'
    expect(response).to have_http_status(:ok)
  end
  it 'não envia com senha errada e limita novos envios' do
    post '/login', params: { email: staff.email, password: 'errada' }
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(response).to have_http_status(:unprocessable_entity)
    request_code
    post '/login', params: { email: staff.email, password: 'senha-para-teste-123' }
    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end
  it 'rejeita código expirado' do
    code = request_code
    travel 11.minutes do
      post '/login/verify', params: { code: code }
      expect(response).to redirect_to('/login')
    end
  end
  it 'bloqueia o código após cinco erros e não aceita reutilização' do
    code = request_code
    5.times { post '/login/verify', params: { code: 'invalid' } }
    post '/login/verify', params: { code: code }
    expect(response).to have_http_status(:unprocessable_entity)
    get '/'
    expect(response).to redirect_to('/login')
  end
  it 'não permite completar desafio após revogação do acesso' do
    code = request_code
    staff.update!(session_version: staff.session_version + 1)
    post '/login/verify', params: { code: code }
    expect(response).to redirect_to('/login')
  end
  it 'preserva autenticação fechada quando SMTP falha' do
    allow(LoginMailer).to receive_message_chain(:verification, :deliver_now).and_raise(Net::SMTPAuthenticationError.new("535 Authentication failed"))
    post '/login', params: { email: staff.email, password: 'senha-para-teste-123' }
    expect(response).to have_http_status(:service_unavailable)
    expect(staff.reload.email_code_digest).to be_nil
    get '/'
    expect(response).to redirect_to('/login')
  end
end
