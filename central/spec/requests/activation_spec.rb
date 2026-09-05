require 'rails_helper'
RSpec.describe 'Ativação e login', type: :request do
  let(:staff) { Staff.create!(name: 'Ana', email: 'ana@example.test', role: 'suporte') }
  it 'configura senha e TOTP e permite login com próximo código' do
    token = staff.activation_token!
    get '/activate', params: { token: token }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<svg')
    patch '/activate', params: { token: token, password: 'senha-segura-1234', password_confirmation: 'senha-segura-1234', code: ROTP::TOTP.new(staff.otp_secret).now }
    expect(response).to redirect_to('/login')
    expect(staff.reload.activated_at).to be_present
    travel 31.seconds do
      post '/login', params: { email: staff.email, password: 'senha-segura-1234', code: ROTP::TOTP.new(staff.otp_secret).now }
      expect(response).to redirect_to('/')
    end
    get '/activate', params: { token: token }
    expect(response).to have_http_status(:not_found)
  end
  it 'não ativa senha fraca nem aceita apenas a senha para entrar' do
    token = staff.activation_token!
    patch '/activate', params: { token: token, password: '123', password_confirmation: '123', code: ROTP::TOTP.new(staff.otp_secret).now }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(staff.reload.activated_at).to be_nil
    staff.update!(password: 'senha-segura-1234', activated_at: Time.current)
    post '/login', params: { email: staff.email, password: 'senha-segura-1234' }
    expect(response).to have_http_status(:unprocessable_entity)
    get '/'
    expect(response).to redirect_to('/login')
  end
end
