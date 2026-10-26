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

  context "com acesso restrito do analista pelo perfil existente" do
    let(:reviewer) do
      profile = Profile.create!(tenant: admin.tenant, name: "Análise Meta #{SecureRandom.hex(4)}",
        axis: "vertical", position: 700,
        permissions: { "leads" => { "view" => true, "edit" => true, "scope" => "own" } })
      create(:admin_user, tenant: admin.tenant, profile: profile)
    end

    before do
      sign_out admin
      sign_in reviewer
      allow(Instagram::Reply).to receive(:call)
    end

    it "permite responder ao próprio lead sem liberar configurações da integração" do
      lead.update!(admin_user: reviewer)
      post reply_instagram_admin_lead_path(lead), params: { body: "Demonstração autorizada" }

      expect(Instagram::Reply).to have_received(:call).with(lead: lead, body: "Demonstração autorizada", admin_user: reviewer)
      expect(response).to redirect_to(admin_lead_path(lead, anchor: "lead-instagram-thread"))

      get admin_meta_integrations_path
      expect(response).to redirect_to(admin_root_path)
      expect(MetaSyncJob).not_to have_been_enqueued
      patch conversion_config_admin_meta_integrations_path,
        params: { meta_conversion_config: { enabled: false } }
      expect(response).to redirect_to(admin_root_path)
    end

    it "recusa responder e ler lead de outro responsável da mesma conta" do
      lead.update!(admin_user: admin)
      post reply_instagram_admin_lead_path(lead), params: { body: "Não autorizado" }
      expect(response).to redirect_to(admin_leads_path)
      expect(Instagram::Reply).not_to have_received(:call)

      get admin_lead_path(lead)
      expect(response).to redirect_to(admin_leads_path)
      expect(response.body).not_to include(lead.email)
    end

    it "recusa lead de outra conta mesmo com o identificador conhecido" do
      other_tenant = Tenant.create!(name: "Outra imobiliária", slug: "meta-review-#{SecureRandom.hex(4)}", active: true)
      other_lead = create(:lead, tenant: other_tenant, instagram_account_id: "outra-conta", instagram_scoped_id: "outro-remetente")

      post reply_instagram_admin_lead_path(other_lead), params: { body: "Não autorizado" }
      expect(response).to have_http_status(:not_found)
      expect(Instagram::Reply).not_to have_received(:call)
    end
  end
end
