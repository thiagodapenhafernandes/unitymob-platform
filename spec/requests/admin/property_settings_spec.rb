require "rails_helper"

RSpec.describe "Admin::PropertySettings", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "allows system admins to configure the property watermark" do
    admin = create(:admin_user, :admin)
    sign_in admin

    get edit_admin_property_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Mídia e marca d'água")
    expect(response.body).to include("property-settings-workspace")
    expect(response.body).to include("property-settings-preview-panel")
    expect(response.body).to include("property-settings-action-footer")
    expect(response.body).to include("Marca d&#39;água das fotos")
    expect(response.body).to include("Tamanho da marca")
    expect(response.body).to include("Opacidade da marca")
    expect(response.body).to include("Prévia")

    patch admin_property_setting_path, params: {
      property_setting: {
        watermark_position: "bottom_right",
        watermark_size_percentage: 44,
        watermark_opacity_percentage: 65,
        watermark_image: png_upload("watermark.png", "120x60", "none", "white")
      }
    }

    expect(response).to redirect_to(edit_admin_property_setting_path)

    setting = PropertySetting.instance
    expect(setting.watermark_position).to eq("bottom_right")
    expect(setting.watermark_size_percentage).to eq(44)
    expect(setting.watermark_opacity_percentage).to eq(65)
    expect(setting.watermark_image).to be_attached
  end

  it "shows the current watermark image when one is already attached" do
    setting = PropertySetting.instance
    setting.watermark_image.attach(png_upload("marca-atual.png", "120x60", "none", "white"))

    admin = create(:admin_user, :admin)
    sign_in admin

    get edit_admin_property_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Arquivo atual")
    expect(response.body).to include("marca-atual.png")
    expect(response.body).to include("Remover imagem atual")
  end

  it "explica o fluxo de captação, revisão e publicação em linguagem operacional" do
    admin = create(:admin_user, :admin)
    setting = PropertySetting.instance
    setting.update!(
      broker_capture_layer_enabled: true,
      required_broker_intake_checks: %w[proprietario endereco fotos],
      returnable_intake_edit_sections: %w[proprietario fotos]
    )

    sign_in admin

    get review_workflow_admin_property_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Regra de entrada, revisão e site")
    expect(response.body).to include("Captador preenche")
    expect(response.body).to include("Sistema confere")
    expect(response.body).to include("Admin aprova ou devolve")
    expect(response.body).to include("O site só recebe o imóvel quando o responsável clicar em Publicar Site")
    expect(response.body).to include("Esta regra vale para captações e fichas internas de captação")
    expect(response.body).to include("O cadastro direto em Imóveis cria um imóvel administrativo e não entra neste fluxo")
    expect(response.body).to include("Imóvel direto")
    expect(response.body).to include("Ficha interna")
    expect(response.body).to include("O que precisa estar completo para mandar análise")
    expect(response.body).to include("Se devolver ao captador, o que ele pode corrigir?")
    expect(response.body).to include("Aprovação administrativa")
    expect(response.body).to include("Sempre manual")
    expect(response.body).to include("Fora da revisão")
  end

  it "deixa claro que revisão desligada não publica automaticamente" do
    admin = create(:admin_user, :admin)
    setting = PropertySetting.instance
    setting.update!(
      broker_capture_layer_enabled: false,
      broker_capture_fallback_admin_user: admin
    )

    sign_in admin

    get review_workflow_admin_property_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sem revisão:")
    expect(response.body).to include("O sistema não publica sozinho")
    expect(response.body).to include("A ficha fica aprovada para o captador publicar")
    expect(response.body).to include("Próximo passo após checklist")
    expect(response.body).to include("Publicar Site")
  end

  it "versiona e audita alterações do fluxo com impacto do tenant" do
    admin = create(:admin_user, :admin)
    setting = PropertySetting.instance
    intake = create(:habitation, :broker_intake, tenant: admin.tenant, admin_user: admin, intake_status: "submitted_for_admin_review")
    sign_in admin

    expect do
      patch admin_property_setting_path, params: {
        return_to: review_workflow_admin_property_setting_path,
        property_setting: {
          broker_capture_layer_enabled: "true",
          notify_internal_review_events: "false",
          required_broker_intake_checks: %w[proprietario endereco fotos],
          returnable_intake_edit_sections: %w[proprietario fotos]
        }
      }
    end.to change(PropertyReviewPolicyAuditLog, :count).by(1)

    audit = PropertyReviewPolicyAuditLog.last
    expect(response).to redirect_to(review_workflow_admin_property_setting_path)
    expect(setting.reload.review_policy_version).to eq(2)
    expect(audit).to have_attributes(tenant_id: admin.tenant_id, admin_user_id: admin.id, version: 2)
    expect(audit.changeset).to include("notify_internal_review_events")
    expect(audit.impact_snapshot).to include("in_progress" => 1, "awaiting_review" => 1)
    expect(audit.policy_snapshot).to include("notify_internal_review_events" => false)
    expect(intake.reload.intake_status).to eq("submitted_for_admin_review")
  end

  it "restaura uma política auditada como nova versão sem reescrever o histórico" do
    admin = create(:admin_user, :admin)
    setting = PropertySetting.instance
    sign_in admin

    patch admin_property_setting_path, params: {
      property_setting: { notify_internal_review_events: "false", required_broker_intake_checks: %w[proprietario fotos] }
    }
    version_to_restore = PropertyReviewPolicyAuditLog.last

    patch admin_property_setting_path, params: {
      property_setting: { notify_internal_review_events: "true", required_broker_intake_checks: %w[proprietario endereco fotos] }
    }
    expect(setting.reload.review_policy_version).to eq(3)

    expect do
      patch restore_review_policy_admin_property_setting_path, params: {
        audit_id: version_to_restore.id,
        confirm_operational_impact: "true"
      }
    end.to change(PropertyReviewPolicyAuditLog, :count).by(1)

    expect(response).to redirect_to(review_workflow_admin_property_setting_path)
    expect(setting.reload).to have_attributes(review_policy_version: 4, notify_internal_review_events: false)
    expect(setting.required_broker_intake_checks).to match_array(%w[proprietario fotos])
    expect(PropertyReviewPolicyAuditLog.last.policy_snapshot).to include("notify_internal_review_events" => false)
    expect(version_to_restore.reload.version).to eq(2)
  end

  it "não permite restaurar auditoria de política de outro tenant" do
    admin = create(:admin_user, :admin)
    other_tenant = Tenant.create!(name: "Outro fluxo #{SecureRandom.hex(3)}", slug: "outro-fluxo-#{SecureRandom.hex(3)}")
    other_admin = create(:admin_user, :admin, tenant: other_tenant)
    other_setting = PropertySetting.create!(tenant: other_tenant)
    other_audit = PropertyReviewPolicyAuditLog.create!(
      tenant: other_tenant,
      property_setting: other_setting,
      admin_user: other_admin,
      version: 2,
      changeset: { "notify_internal_review_events" => { "before" => true, "after" => false } },
      impact_snapshot: { "in_progress" => 0 },
      policy_snapshot: PropertyReviewPolicy::ChangeRecorder.snapshot(other_setting)
    )
    sign_in admin

    expect do
      patch restore_review_policy_admin_property_setting_path, params: { audit_id: other_audit.id, confirm_operational_impact: "true" }
    end.not_to change(PropertyReviewPolicyAuditLog, :count)

    expect(response).to have_http_status(:not_found)
    expect(PropertySetting.instance.review_policy_version).to eq(1)
  end

  it "não cria nova versão quando apenas a marca d'água muda" do
    admin = create(:admin_user, :admin)
    setting = PropertySetting.instance
    sign_in admin

    expect do
      patch admin_property_setting_path, params: { property_setting: { watermark_position: "bottom_right" } }
    end.not_to change(PropertyReviewPolicyAuditLog, :count)

    expect(setting.reload.review_policy_version).to eq(1)
  end

  it "requires fallback admin user when disabling broker capture review layer" do
    admin = create(:admin_user, :admin)
    gerente = Tenant.default.profiles.vertical.find_by!(name: Profile::INTERNAL_MANAGEMENT_PROFILE_NAME)
    administrativo = Tenant.default.profiles.find_by!(key: "administrativo")
    gerente.update!(permissions: Profile.default_permissions_for("Administrativo"))
    administrativo.update!(permissions: Profile.default_permissions_for("Administrativo"))
    fallback = create(:admin_user, profile: gerente, horizontal_profile: administrativo)
    other_admin = create(:admin_user, :admin, name: "Outro admin")
    intake = create(:habitation, :broker_intake, admin_user: other_admin, intake_status: "draft")
    intake.update_column(:admin_user_id, other_admin.id)

    sign_in admin

    patch admin_property_setting_path, params: {
      property_setting: {
        broker_capture_layer_enabled: "false"
      }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("deve ser informado")

    patch admin_property_setting_path, params: {
      confirm_operational_impact: "true",
      property_setting: {
        broker_capture_layer_enabled: "false",
        broker_capture_fallback_admin_user_id: fallback.id
      }
    }

    expect(response).to redirect_to(edit_admin_property_setting_path)
    expect(intake.reload.admin_user_id).to eq(fallback.id)
  end

  it "simula mudanças sem salvar nem criar auditoria" do
    admin = create(:admin_user, :admin)
    setting = PropertySetting.instance
    sign_in admin

    expect do
      patch admin_property_setting_path, params: {
        simulate_review_policy: "true",
        return_to: review_workflow_admin_property_setting_path,
        property_setting: { notify_internal_review_events: "false" }
      }
    end.not_to change(PropertyReviewPolicyAuditLog, :count)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Comparação com a política vigente")
    expect(response.body).to include("Notificação interna")
    expect(setting.reload.notify_internal_review_events).to be(true)
  end

  it "exige confirmação backend antes de reatribuir captações" do
    admin = create(:admin_user, :admin)
    fallback = admin
    intake = create(:habitation, :broker_intake, tenant: admin.tenant, admin_user: admin, intake_status: "draft")
    setting = PropertySetting.instance
    sign_in admin

    expect do
      patch admin_property_setting_path, params: {
        return_to: review_workflow_admin_property_setting_path,
        property_setting: { broker_capture_layer_enabled: "false", broker_capture_fallback_admin_user_id: fallback.id }
      }
    end.not_to change(PropertyReviewPolicyAuditLog, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Confirme a reatribuição")
    expect(setting.reload.broker_capture_layer_enabled).to be(true)
    expect(intake.reload.admin_user_id).to eq(admin.id)
  end

  it "blocks non-admin users" do
    user = create(:admin_user)
    sign_in user

    get edit_admin_property_setting_path

    expect(response).to redirect_to(admin_root_path)
  end

  def png_upload(filename, size, background, fill)
    file = Tempfile.new([File.basename(filename, ".png"), ".png"])
    file.close
    system("magick", "-size", size, "xc:#{background}", "-fill", fill, "-draw", "rectangle 10,10 90,40", file.path, exception: true)
    Rack::Test::UploadedFile.new(file.path, "image/png", original_filename: filename)
  end
end
