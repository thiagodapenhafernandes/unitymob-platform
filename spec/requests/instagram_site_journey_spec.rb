require 'rails_helper'

RSpec.describe 'Jornada Instagram para o site', type: :request do
  let(:tenant) { Tenant.default }
  let(:lead) { create(:lead, tenant: tenant, name: '@edna', phone: nil, email: nil, instagram_account_id: '12345', instagram_scoped_id: '98765', skip_automatic_routing: true) }
  let(:property) { create(:habitation, tenant: tenant) }
  let(:token) { Instagram::PropertyJourney.reference(lead) }

  before do
    host! 'localhost'
    Tenants::LocalPublicHostOverride.clear!
    allow_any_instance_of(Tenant).to receive(:public_base_url).and_return('http://localhost')
    allow(WebhookService).to receive(:send_form_data)
    allow(LeadMailer).to receive(:with).and_return(double(welcome_lead: double(deliver_later: nil)))
  end

  Tenant::PUBLIC_SITE_THEMES.each_key do |theme|
    it "registra a conversão no contato do Instagram no tema #{theme}" do
      tenant.update_columns(public_site_theme: theme)
      cookies[ApplicationController::LGPD_CONSENT_COOKIE] = 'accepted'
      get habitation_path(property), params: {ig_ref: token}
      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(lead.activities.where(kind: 'instagram_property_event').pluck(:metadata).map { |m| m['event'] }).to include('opened')
      expect {
        post leads_path, params: {lead: {name: 'Edna Azevedo', phone: '(47) 99888-7777', property_id: property.id, page_url: "http://localhost/imoveis/#{property.slug}"}}, as: :json
      }.not_to change(Lead, :count)
      expect(response).to have_http_status(:ok)
      expect(lead.reload).to have_attributes(client_name: 'Edna Azevedo', name: 'Edna Azevedo', property_id: property.id)
      expect(lead.property_interests.pluck(:habitation_id)).to eq([property.id])
      expect(lead.activities.where(kind: 'instagram_property_event').pluck(:metadata).map { |m| m['event'] }).to include('converted')
    end
  end

  it 'não registra navegação sem consentimento e ainda reconhece a referência explícita do formulário' do
    cookies[ApplicationController::LGPD_CONSENT_COOKIE] = 'rejected'
    get habitation_path(property), params: {ig_ref: token}
    expect(lead.activities.where(kind: 'instagram_property_event')).to be_empty
    page = "http://localhost/imoveis/#{property.slug}?#{ {ig_ref: token}.to_query }"
    expect {
      post leads_path, params: {lead: {name: 'Edna', phone: '(47) 99888-7777', property_id: property.id, page_url: page}}, as: :json
    }.not_to change(Lead, :count)
    expect(response).to have_http_status(:ok)
    expect(lead.reload.client_name).to eq('Edna')
  end
end
