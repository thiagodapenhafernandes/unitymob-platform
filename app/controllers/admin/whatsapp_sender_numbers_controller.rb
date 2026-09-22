class Admin::WhatsappSenderNumbersController < Admin::BaseController
  before_action :authorize_sender_number_management!
  before_action :set_sender_number, only: [:update, :destroy, :test_connection, :reactivate, :connect]

  def create
    @sender_number = current_tenant.whatsapp_sender_numbers.new(sender_number_params)
    @sender_number.status = "connected"
    @sender_number.active = true

    if @sender_number.save
      redirect_after_save("Número WhatsApp adicionado.")
    else
      redirect_to sender_number_return_path(admin_whatsapp_campaigns_path), alert: @sender_number.errors.full_messages.to_sentence
    end
  end

  def update
    if @sender_number.update(sender_number_params)
      redirect_after_save("Parâmetros do número atualizados.")
    else
      redirect_to sender_number_return_path(admin_whatsapp_campaigns_path(whatsapp_sender_number_id: @sender_number.id)), alert: @sender_number.errors.full_messages.to_sentence
    end
  end

  # Reprocessa a conexão com a Meta (validação, inscrição do app na WABA e rota no gateway).
  def connect
    redirect_after_save("Conexão do número reprocessada.")
  end

  def destroy
    @sender_number.update!(active: false, status: "disconnected", use_for_notifications: false)
    redirect_to sender_number_return_path(admin_whatsapp_campaigns_path), notice: "Número WhatsApp desativado."
  end

  def reactivate
    @sender_number.update!(active: true, status: "pending")
    redirect_to sender_number_return_path(admin_whatsapp_integration_path), notice: "Número WhatsApp reativado."
  end

  def test_connection
    client = Whatsapp::CloudClient.new(@sender_number)

    unless client.configured?
      return render json: { ok: false, message: "Configure Access Token e Phone Number ID antes de testar." }, status: :unprocessable_content
    end

    phone = client.phone_info
    subscriptions = client.subscribed_apps
    subscribed_apps = Array(subscriptions.dig(:data, "data"))

    render json: {
      ok: phone[:ok] && subscriptions[:ok] && subscribed_apps.any?,
      send: {
        ok: phone[:ok],
        label: phone.dig(:data, "display_phone_number").presence || phone.dig(:data, "verified_name"),
        error: phone[:error]
      },
      receive: {
        ok: subscriptions[:ok] && subscribed_apps.any?,
        error: subscriptions[:error],
        apps: subscribed_apps.filter_map { |app| app.dig("whatsapp_business_api_data", "name") }
      }
    }
  end

  private

  def redirect_after_save(message)
    flash_type = :notice
    if @sender_number.active?
      result = Whatsapp::SenderNumberConnector.call(
        @sender_number,
        tenant: current_tenant,
        target_url: webhooks_whatsapp_url(host: request.host_with_port, protocol: request.protocol.delete("://"))
      )
      if result.warnings.any?
        flash_type = :alert
        message += " Atenção: #{result.warnings.join(' ')}"
      elsif !result.skipped?
        message += " Número validado na Meta, app inscrito na WABA e rota registrada."
      end
    end
    redirect_to sender_number_return_path(admin_whatsapp_campaigns_path(whatsapp_sender_number_id: @sender_number.id)), flash_type => message
  end

  def set_sender_number
    @sender_number = current_tenant.whatsapp_sender_numbers.find(params[:id])
  end

  def sender_number_params
    permitted = params.require(:whatsapp_sender_number).permit(
      :label,
      :display_phone_number,
      :phone_number_id,
      :waba_id,
      :verified_name,
      :quality_rating,
      :use_for_notifications,
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

  def authorize_sender_number_management!
    check_any_permission!(
      [:manage, :whatsapp_campaigns],
      [:manage, :integracoes]
    )
  end

  def sender_number_return_path(default_path)
    value = params[:return_to].to_s
    return default_path if value.blank?
    return value if value.start_with?("/") && !value.start_with?("//")

    default_path
  end
end
