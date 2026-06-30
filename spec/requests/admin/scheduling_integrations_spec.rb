require "rails_helper"

RSpec.describe "Admin::SchedulingIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "salva a url externa da agenda de fotos" do
    get admin_scheduling_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Agenda de fotografia")

    patch admin_scheduling_integration_path, params: {
      scheduling: { photography_schedule_url: "https://calendly.com/fotografias-saluteimoveis/30min" }
    }

    expect(response).to redirect_to(admin_scheduling_integration_path)
    expect(Setting.get("photography_schedule_url")).to eq("https://calendly.com/fotografias-saluteimoveis/30min")
  end

  it "bloqueia e libera dias da agenda interna" do
    post block_day_admin_scheduling_integration_path, params: {
      photography_schedule_block: { date: Date.current.next_day.to_s, reason: "Treinamento" }
    }

    block = PhotographyScheduleBlock.last
    expect(response).to redirect_to(admin_scheduling_integration_path)
    expect(block.date).to eq(Date.current.next_day)
    expect(block.reason).to eq("Treinamento")
    expect(block.created_by).to eq(admin)

    delete unblock_day_admin_scheduling_integration_path(block)

    expect(response).to redirect_to(admin_scheduling_integration_path)
    expect(PhotographyScheduleBlock.exists?(block.id)).to be(false)
  end

  it "permite que perfil fotografo veja agenda e pendencias sem gerenciar bloqueios" do
    profile = Profile.create!(
      tenant: Tenant.default,
      name: "Fotógrafo teste",
      active: true,
      position: 650,
      permissions: {
        "admin" => false,
        "agenda_fotografia" => { "view" => true, "manage" => false }
      }
    )
    photographer = create(:admin_user, profile: profile)
    habitation = create(:habitation, :broker_intake, titulo_anuncio: "Apartamento com fotos pendentes")

    sign_out admin
    sign_in photographer

    get admin_scheduling_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Apartamento com fotos pendentes")
    expect(response.body).not_to include("Bloquear dia")

    get pending_property_admin_scheduling_integration_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Dados para fotografia")
    expect(response.body).to include("Apartamento com fotos pendentes")

    patch admin_scheduling_integration_path, params: {
      scheduling: { photography_schedule_url: "https://example.com/agenda" }
    }

    expect(response).to redirect_to(admin_root_path)
    expect(Setting.get("photography_schedule_url")).not_to eq("https://example.com/agenda")
  end
end
