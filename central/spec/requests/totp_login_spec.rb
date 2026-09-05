require 'rails_helper'
RSpec.describe 'Login em duas etapas', type: :request do
  before { freeze_time }
  let!(:staff) { Staff.create!(name: 'Admin', email: 'admin@example.test', role: 'admin', password: 'senha-segura-1234', activated_at: Time.current, otp_secret: ROTP::Base32.random) }
  def password_step
    post '/login', params: { email: staff.email, password: 'senha-segura-1234' }
  end
  def code_step(code = ROTP::TOTP.new(staff.otp_secret).now)
    post '/login/authenticator', params: { code: code }
  end
  it 'exige senha e código em etapas separadas sem liberar sessão intermediária' do
    code_step
    expect(response).to redirect_to('/login')
    password_step
    expect(response).to redirect_to('/login/authenticator')
    get '/'
    expect(response).to redirect_to('/login')
    get '/login/authenticator'
    expect(response.body).to include('Etapa 2 de 2')
    expect(response.body).not_to include('type="password"', '<details>')
    code_step
    expect(response).to redirect_to('/')
    expect(staff.staff_sessions.count).to eq(1)
    code_step
    expect(response).to redirect_to('/login')
  end
  it 'expira a etapa e invalida o desafio após revogação' do
    password_step
    travel 11.minutes do
      code_step
      expect(response).to redirect_to('/login')
    end
    password_step
    staff.update!(session_version: staff.session_version + 1)
    code_step
    expect(response).to redirect_to('/login')
  end
  it 'informa prazo sem renovar bloqueio ou zerar erros com senha correta' do
    password_step
    5.times { code_step('invalid') }
    expect(response.body).to include('15 minutos')
    locked_until = staff.reload.locked_until
    password_step
    expect(response.body).to include('15 minutos')
    expect(staff.reload.locked_until).to eq(locked_until)
    travel 2.minutes do
      password_step
      expect(response.body).to include('13 minutos')
      expect(staff.reload.locked_until).to eq(locked_until)
    end
    travel 16.minutes do
      password_step
      code_step('invalid')
      expect(staff.reload.failed_attempts).to eq(1)
      expect(staff.locked_until).to be_nil
      code_step
      expect(response).to redirect_to('/')
    end
  end
  it 'não aceita reutilizar código da ativação' do
    staff.verify_otp!(ROTP::TOTP.new(staff.otp_secret).now)
    password_step
    code_step
    expect(response.body).to include('já utilizado')
    expect(staff.staff_sessions.count).to eq(0)
  end
end
