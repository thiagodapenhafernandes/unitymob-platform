class Admin::WhatsappSenderNumbersController < Admin::BaseController
  before_action -> { check_permission!(:manage, :whatsapp_campaigns) }
  before_action :set_sender_number, only: [:update, :destroy]

  def create
    @sender_number = WhatsappSenderNumber.new(sender_number_params)
    @sender_number.status = "connected"
    @sender_number.active = true

    if @sender_number.save
      redirect_to admin_whatsapp_campaigns_path(whatsapp_sender_number_id: @sender_number.id), notice: "Número WhatsApp adicionado."
    else
      redirect_to admin_whatsapp_campaigns_path, alert: @sender_number.errors.full_messages.to_sentence
    end
  end

  def update
    if @sender_number.update(sender_number_params)
      redirect_to admin_whatsapp_campaigns_path(whatsapp_sender_number_id: @sender_number.id), notice: "Parâmetros do número atualizados."
    else
      redirect_to admin_whatsapp_campaigns_path(whatsapp_sender_number_id: @sender_number.id), alert: @sender_number.errors.full_messages.to_sentence
    end
  end

  def destroy
    @sender_number.update!(active: false, status: "disconnected")
    redirect_to admin_whatsapp_campaigns_path, notice: "Número WhatsApp desativado."
  end

  private

  def set_sender_number
    @sender_number = WhatsappSenderNumber.find(params[:id])
  end

  def sender_number_params
    permitted = params.require(:whatsapp_sender_number).permit(
      :label,
      :display_phone_number,
      :phone_number_id,
      :waba_id,
      :verified_name,
      :quality_rating,
      :cpl_sent_unit_price,
      :cpl_fla_unit_price,
      :whatsapp_business_integration_id
    )
    normalize_decimal_param!(permitted, :cpl_sent_unit_price)
    normalize_decimal_param!(permitted, :cpl_fla_unit_price)
    permitted
  end

  def normalize_decimal_param!(permitted, key)
    return unless permitted.key?(key)

    permitted[key] = permitted[key].to_s.tr(",", ".")
  end
end
