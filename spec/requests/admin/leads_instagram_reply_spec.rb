require "rails_helper"

RSpec.describe "Admin::Leads Instagram reply", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "ig-reply-#{SecureRandom.hex(8)}@salute.test") }
  let(:lead) do
    create(:lead, tenant: admin.tenant, origin: "Instagram Direct",
      instagram_account_id: "555", instagram_scoped_id: "777")
  end

  before do
    host! "localhost"
    sign_in admin
  end

  it "envia a resposta e volta à ficha" do
    message = lead.instagram_messages.create!(message_id: "mid-1", body: "Oi",
      occurred_at: 1.hour.ago)
    allow(Instagram::Reply).to receive(:call).and_return(message)

    post reply_instagram_admin_lead_path(lead), params: { body: "Olá!" }

    expect(Instagram::Reply).to have_received(:call)
      .with(hash_including(lead: lead, admin_user: admin))
    expect(response).to redirect_to(%r{/admin/leads/#{lead.id}#lead-instagram-thread})
    expect(flash[:notice]).to include("enviada")
  end

  it "mostra o erro da Meta sem quebrar" do
    allow(Instagram::Reply).to receive(:call)
      .and_raise(Instagram::Reply::Error, "Janela de 24h encerrada.")

    post reply_instagram_admin_lead_path(lead), params: { body: "Oi" }

    expect(response).to redirect_to(%r{/admin/leads/#{lead.id}})
    expect(flash[:alert]).to include("24h")
  end

  it "exibe a thread na ficha do lead" do
    lead.instagram_messages.create!(message_id: "mid-1", body: "Tenho interesse",
      occurred_at: 1.hour.ago)

    get admin_lead_path(lead)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("lead-instagram-thread", "Tenho interesse", "Responder no Instagram")
  end
end
