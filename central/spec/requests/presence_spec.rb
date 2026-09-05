require 'rails_helper'
RSpec.describe 'Presença auditável', type: :request do
  after { travel_back }
  it 'registra login real, confirma somente intervalos observados e registra logout' do
    travel_to Time.zone.parse('2026-09-05 10:00:00')
    staff = central_login
    entry = StaffSession.last
    expect(entry.staff).to eq(staff)
    expect(entry.last_seen_at).to be_nil
    post '/presence'
    expect(response).to have_http_status(:no_content)
    travel 30.seconds
    post '/presence'
    expect(entry.reload).to be_online
    expect(entry.presence_windows.last.confirmed_until - entry.presence_windows.last.started_at).to eq(30)
    travel 2.minutes
    expect(entry.reload).not_to be_online
    expect(entry.ended_at).to be_nil
    post '/presence'
    expect(entry.presence_windows.count).to eq(2)
    delete '/logout'
    expect(entry.reload.end_reason).to eq('logout')
    post '/presence', headers: { 'ACCEPT' => 'application/json' }
    expect(response).to have_http_status(:unauthorized)
  end
  it 'expiração e revogação encerram sessões com motivos distintos' do
    staff = central_login
    entry = StaffSession.last
    staff.update!(session_version: staff.session_version + 1)
    expect(entry.reload.end_reason).to eq('access_changed')
    expired = staff.staff_sessions.create!(role: staff.role, started_at: 9.hours.ago, expires_at: 1.hour.ago)
    StaffSession.expire!
    expect(expired.reload.end_reason).to eq('expired')
    expect(expired.ended_at).to eq(expired.expires_at)
  end
  it 'apenas admin acessa dashboard e configura metas' do
    central_login('suporte')
    get '/sla'
    expect(response).to have_http_status(:forbidden)
    patch '/sla/policies', params: {policies: {normal: {first_response_minutes: 1}}}
    expect(response).to have_http_status(:forbidden)
    delete '/logout'
    central_login('admin')
    get '/sla'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('SLA e atividade', 'Metas de SLA')
    patch '/sla/policies', params: {policies: Support::Ticket::PRIORITIES.index_with { {first_response_minutes: 30, resolution_minutes: 480} }}
    expect(response).to have_http_status(:redirect)
    expect(SlaPolicyChange.count).to eq(3)
  end
end
