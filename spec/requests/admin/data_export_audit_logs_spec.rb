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
    broker_profile = Profile.create!(name: "Perfil export #{SecureRandom.hex(4)}", permissions: Profile.default_permissions_for("Corretor"))
    other_profile = Profile.create!(name: "Outro export #{SecureRandom.hex(4)}", permissions: Profile.default_permissions_for("Gerente"))
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
end
