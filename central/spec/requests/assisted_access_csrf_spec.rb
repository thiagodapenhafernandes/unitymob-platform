require 'rails_helper'

RSpec.describe 'Origem do acesso assistido', type: :request do
  around do |example|
    old_protection = ActionController::Base.allow_forgery_protection
    old_origin_check = ActionController::Base.forgery_protection_origin_check
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = old_protection
    ActionController::Base.forgery_protection_origin_check = old_origin_check
  end

  it 'permite o POST da central com token válido e mantém a proteção contra outra origem' do
    central_login('admin')
    ticket = support_ticket
    ActionController::Base.allow_forgery_protection = true
    ActionController::Base.forgery_protection_origin_check = true
    get '/'
    expect(response.headers['Referrer-Policy']).to eq('same-origin')
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
    allow(Support::Transport).to receive(:post).and_return('token' => 'test-handoff-token')

    post "/admin/support/tickets/#{ticket.id}/access", params: { authenticity_token: token }, headers: { 'Origin' => 'http://localhost' }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('https://salute.example.test/support/access')
    expect(Support::Transport).to have_received(:post).once

    post "/admin/support/tickets/#{ticket.id}/access", params: { authenticity_token: token }, headers: { 'Origin' => 'https://other.example.test' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Support::Transport).to have_received(:post).once
  end
end
