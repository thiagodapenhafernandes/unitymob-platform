# Contato do site público: canais, redes e o atendimento do imóvel. Reúne o que antes
# vivia também em Integrações → WhatsApp → Telefones do site (roteamento por negociação).
class Admin::ContactSettingsController < Admin::BaseController
  requires_permission :manage, :site_publico
  before_action :set_records

  def edit
  end

  def update
    saved = ContactSetting.transaction do
      (@contact_setting.update(contact_setting_params) && @whatsapp_integration.update(routing_params)) || raise(ActiveRecord::Rollback)
    end

    if saved
      redirect_to edit_admin_contact_setting_path, notice: 'Informações de contato atualizadas!'
    else
      @whatsapp_integration.errors.each { |error| @contact_setting.errors.add(:base, error.full_message) }
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_records
    @contact_setting = ContactSetting.instance
    @whatsapp_integration = WhatsappBusinessIntegration.current(current_tenant)
  end

  def contact_setting_params
    params.require(:contact_setting).permit(
      :whatsapp_primary,
      :whatsapp_secondary,
      :phone,
      :email_primary,
      :email_commercial,
      :address,
      :business_hours,
      :facebook_url,
      :instagram_url,
      :youtube_url,
      :blog_url,
      :linkedin_url,
      :sale_lead_success_message,
      :rent_lead_success_message,
      :sale_rent_lead_success_message,
      :sale_whatsapp_message,
      :rent_whatsapp_message,
      :sale_rent_whatsapp_message
    )
  end

  def routing_params
    params.fetch(:whatsapp_business_integration, {}).permit(
      :allow_photo_presentation,
      :default_whatsapp_number,
      :sale_whatsapp_number,
      :rent_whatsapp_number,
      :sale_rent_whatsapp_number,
      :sale_requires_lead_form,
      :rent_requires_lead_form,
      :sale_rent_requires_lead_form,
      :sale_redirect_after_capture,
      :rent_redirect_after_capture,
      :sale_rent_redirect_after_capture
    )
  end
end
