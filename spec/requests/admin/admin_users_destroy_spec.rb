require "rails_helper"

RSpec.describe "Admin users destroy", type: :request do
  include Devise::Test::IntegrationHelpers

  before do
    ActionController::Base.allow_forgery_protection = false
    host! "localhost"
  end

  def setup_tenant
    tenant = Tenant.create!(name: "Tenant destroy #{SecureRandom.hex(3)}", slug: "tenant-destroy-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    agent_profile = tenant.profiles.find_by!(key: "agent")
    owner = create(:admin_user, tenant: tenant, profile: owner_profile, name: "Owner")
    target = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner, name: "Destino")
    doomed = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner, name: "Corretor 2")
    [tenant, owner, target, doomed]
  end

  it "exclui, reatribui e envia uma única notificação agregada ao destino" do
    tenant, owner, target, doomed = setup_tenant
    create(:lead, tenant: tenant, admin_user: doomed)
    create(:lead, tenant: tenant, admin_user: doomed)
    create(:habitation, tenant: tenant, admin_user: doomed)

    sign_in owner

    expect {
      delete admin_admin_user_path(doomed), params: { reassign_to_id: target.id }
    }.to change { InAppNotification.where(admin_user: target).count }.by(1)

    expect(response).to redirect_to(admin_admin_users_path)
    expect(AdminUser.exists?(doomed.id)).to be(false)
    expect(tenant.leads.where(admin_user: target).count).to eq(2)
    notification = InAppNotification.where(admin_user: target).last
    expect(notification.body).to include("1 imóvel e 2 leads")
  end

  it "trunca erro longo no alerta em vez de estourar o cookie" do
    _tenant, owner, target, doomed = setup_tenant
    long_message = "FKs não classificadas: #{('tabela.coluna, ' * 200)}FIM-MARCADOR"
    allow(AdminUsers::HardDeleter).to receive(:call).and_raise(AdminUsers::HardDeleter::Error, long_message)

    sign_in owner
    delete admin_admin_user_path(doomed), params: { reassign_to_id: target.id }

    expect(response).to redirect_to(admin_admin_users_path)
    follow_redirect!
    expect(response.body).to include("Não foi possível excluir o usuário")
    expect(response.body).not_to include("FIM-MARCADOR")
  end
end
