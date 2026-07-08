# Comportamento do ATENDIMENTO WhatsApp (cartão de apresentação etc.).
# A conexão do número/app continua em /admin/whatsapp_integration (Integrações);
# aqui é só política de atendimento — por isso exige a integração pronta.
class Admin::WhatsappServiceSettingsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :whatsapp_inbox) }
  before_action :set_integration
  before_action :require_messaging_ready

  def edit
    PresentationCard.ensure_system_default_for(current_tenant)
  end

  def update
    if @integration.update(service_settings_params)
      redirect_to edit_admin_whatsapp_service_setting_path, notice: "Configurações do atendimento salvas."
    else
      flash.now[:alert] = @integration.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_integration
    @integration = WhatsappBusinessIntegration.current(current_tenant)
  end

  def require_messaging_ready
    return if @integration&.messaging_ready?

    redirect_to admin_whatsapp_integration_path,
                alert: "Conecte o WhatsApp da empresa antes de configurar o atendimento."
  end

  def service_settings_params
    params.require(:whatsapp_business_integration).permit(
      :presentation_enabled,
      :require_presentation,
      :allow_photo_presentation,
      :inbox_attendance_enabled
    )
  end
end
