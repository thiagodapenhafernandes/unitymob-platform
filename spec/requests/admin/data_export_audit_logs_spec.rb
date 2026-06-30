require "rails_helper"

RSpec.describe "Admin::DataExportAuditLogs", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "data-export-#{SecureRandom.hex(8)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "records habitation CSV exports" do
    create(:habitation, codigo: "EXP-#{SecureRandom.hex(6)}", titulo_anuncio: "Exportável")

    expect {
      post export_admin_habitations_path(format: :json),
           params: { fields: %w[codigo categoria], data_format: "csv_semicolon" },
           headers: { "ACCEPT" => "application/json" }
    }.to change(DataExportAuditLog, :count).by(1)

    log = DataExportAuditLog.last
    expect(response).to have_http_status(:ok)
    expect(log).to have_attributes(
      admin_user_id: admin.id,
      export_type: "csv_export",
      resource_name: "habitations",
      format: "csv_semicolon"
    )
    expect(log.record_count).to be >= 1
    expect(log.fields).to include("codigo", "categoria")
  end

  it "records proprietor CSV exports and renders audit page" do
    create(:proprietor, name: "Maria Exportação")

    expect {
      get export_admin_proprietors_path, params: { fields: %w[name phone_primary], data_format: "csv" }
    }.to change(DataExportAuditLog, :count).by(1)

    get admin_data_export_audit_logs_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Auditoria de Exportações")
    expect(response.body).to include("Proprietários")
    expect(response.body).to include("Limpar")
  end

  it "filtra exportações por perfil, usuário, formato e arquivo" do
    broker_profile = Profile.create!(tenant: admin.tenant, name: "Perfil export #{SecureRandom.hex(4)}", axis: "vertical", position: 8_900, permissions: Profile.default_permissions_for("Corretor"))
    other_profile = Profile.create!(tenant: admin.tenant, name: "Outro export #{SecureRandom.hex(4)}", axis: "vertical", position: 700, permissions: Profile.default_permissions_for("Gerente"))
    broker = create(:admin_user, profile: broker_profile, name: "Exportador Certo")
    other = create(:admin_user, profile: other_profile, name: "Exportador Errado")

    create(:data_export_audit_log, admin_user: broker, format: "csv_semicolon", filename: "captações-maio.csv", resource_name: "captacoes")
    create(:data_export_audit_log, admin_user: other, format: "pdf", filename: "imoveis.pdf", resource_name: "habitations")

    get admin_data_export_audit_logs_path, params: {
      profile_id: broker_profile.id,
      admin_user_id: broker.id,
      data_format: "csv_semicolon",
      filename: "captações"
    }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Exportador Certo")
    expect(response.body).to include("captações-maio.csv")
    expect(response.body).not_to include("imoveis.pdf")
  end

  it "não exibe exportações de outro Tenant" do
    other_tenant = Tenant.create!(name: "Outro export #{SecureRandom.hex(3)}", slug: "outro-export-#{SecureRandom.hex(3)}")
    other_profile = other_tenant.profiles.find_by!(key: "agent")
    other_user = create(:admin_user, tenant: other_tenant, profile: other_profile)
    create(:data_export_audit_log, admin_user: admin, filename: "tenant-atual.csv", resource_name: "habitations")
    create(:data_export_audit_log, admin_user: other_user, filename: "tenant-outro.csv", resource_name: "habitations")

    get admin_data_export_audit_logs_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("tenant-atual.csv")
    expect(response.body).not_to include("tenant-outro.csv")
  end

  it "limita auditoria de exportações à subárvore do perfil vertical intermediário" do
    tenant = admin.tenant
    owner = admin
    manager_profile = Profile.create!(
      tenant: tenant,
      name: "Gestor Auditoria Export #{SecureRandom.hex(4)}",
      axis: "vertical",
      position: 720,
      permissions: {
        "dashboard" => { "view" => true },
        "data_export_audit" => { "view" => true, "scope" => "team" }
      }
    )
    agent_profile = tenant.profiles.find_by!(key: "agent")
    manager = create(:admin_user, tenant: tenant, profile: manager_profile, manager: owner, name: "Gestor Exportação")
    subordinate = create(:admin_user, tenant: tenant, profile: agent_profile, manager: manager, name: "Subordinado Exportação")
    peer = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner, name: "Par Exportação")

    create(:data_export_audit_log, admin_user: manager, filename: "gestor.csv")
    create(:data_export_audit_log, admin_user: subordinate, filename: "subordinado.csv")
    create(:data_export_audit_log, admin_user: peer, filename: "par-fora.csv")
    create(:data_export_audit_log, admin_user: owner, filename: "dono-acima.csv")

    sign_in manager

    get admin_data_export_audit_logs_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("gestor.csv")
    expect(response.body).to include("subordinado.csv")
    expect(response.body).not_to include("par-fora.csv")
    expect(response.body).not_to include("dono-acima.csv")
    expect(response.body).not_to include("Par Exportação")
  end
end
