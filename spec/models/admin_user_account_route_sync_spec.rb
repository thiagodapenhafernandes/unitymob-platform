require "rails_helper"

RSpec.describe AdminUser, "discovery do app híbrido" do
  it "enfileira a sincronização ao criar um admin_user comum" do
    expect {
      create(:admin_user, email: "novo-corretor-#{SecureRandom.hex(4)}@salute.test")
    }.to have_enqueued_job(Mobile::SyncAccountRouteJob)
  end

  it "enfileira a sincronização quando o e-mail muda" do
    admin_user = create(:admin_user, email: "antigo-#{SecureRandom.hex(4)}@salute.test")

    expect {
      admin_user.update!(email: "novo-#{SecureRandom.hex(4)}@salute.test")
    }.to have_enqueued_job(Mobile::SyncAccountRouteJob).with(admin_user.id)
  end

  it "não enfileira nada quando um update não muda o e-mail" do
    admin_user = create(:admin_user, email: "estavel-#{SecureRandom.hex(4)}@salute.test")

    expect {
      admin_user.update!(name: "Novo Nome")
    }.not_to have_enqueued_job(Mobile::SyncAccountRouteJob)
  end

  it "não sincroniza Admin do Sistema" do
    expect {
      create(:admin_user, super_admin: true, tenant: nil, profile: nil)
    }.not_to have_enqueued_job(Mobile::SyncAccountRouteJob)
  end

  it "enfileira a desativação ao destruir um admin_user" do
    admin_user = create(:admin_user, email: "sai-#{SecureRandom.hex(4)}@salute.test")

    expect {
      admin_user.destroy!
    }.to have_enqueued_job(Mobile::DeactivateAccountRouteJob).with(admin_user.email)
  end
end
