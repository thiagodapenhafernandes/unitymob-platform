ENV['RAILS_ENV'] = 'test'
require_relative '../config/environment'
require 'rspec/rails'
RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.include ActiveSupport::Testing::TimeHelpers
  config.before { Rack::Attack.reset! }
  config.before { host! 'localhost' if respond_to?(:host!) }
end

def support_account
  Support::Account.create!(uid: SecureRandom.uuid, name: 'Salute', endpoint: 'https://salute.example.test', secret: 's' * 64)
end

def support_ticket(account = support_account)
  account.tickets.create!(subject: 'Não consigo salvar o imóvel', requester_id: '12', requester_name: 'Maria', intake: Support::Ticket::QUESTIONS.keys.index_with { 'Detalhes do problema' })
end

def central_login(role = 'suporte')
  staff = Staff.create!(name: 'Ana', email: "#{SecureRandom.hex(4)}@unitymob.test", role: role, password: 'uma-senha-longa-123', password_confirmation: 'uma-senha-longa-123', otp_secret: ROTP::Base32.random, activated_at: Time.current)
  post '/login', params: { email: staff.email, password: 'uma-senha-longa-123', code: ROTP::TOTP.new(staff.otp_secret).now }
  expect(response).to redirect_to('/login/authenticator')
  post '/login/authenticator', params: { code: ROTP::TOTP.new(staff.otp_secret).now }
  expect(response).to redirect_to('/')
  staff
end
