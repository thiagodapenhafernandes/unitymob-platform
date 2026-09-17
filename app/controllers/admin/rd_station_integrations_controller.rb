class Admin::RdStationIntegrationsController < Admin::BaseController
  requires_permission :manage, :integracoes

  def show
    load_setting
  end

  def connect
    load_setting
    unless @rd_station_setting.client_configured?
      return redirect_to admin_rd_station_integration_path, alert: "Informe Client ID e Client secret antes de conectar a RD Station."
    end

    state = SecureRandom.hex(24)
    session[:rd_station_oauth_state] = state
    redirect_to rd_client.authorization_url(redirect_uri: callback_url, state:), allow_other_host: true
  end

  def callback
    load_setting
    if params[:state].blank? || params[:state] != session.delete(:rd_station_oauth_state)
      return redirect_to admin_rd_station_integration_path, alert: "Não foi possível validar o retorno da RD Station."
    end

    tokens = rd_client.exchange_code!(code: params[:code], redirect_uri: callback_url)
    RdStationIntegrationSetting.save_oauth_tokens!(tenant: current_tenant, payload: tokens)
    redirect_to admin_rd_station_integration_path, notice: "RD Station conectada com sucesso."
  rescue StandardError => e
    redirect_to admin_rd_station_integration_path, alert: e.message
  end

  def sync_webhooks
    load_setting
    unless @rd_station_setting.connected? && @rd_station_setting.webhook_secret_configured?
      return redirect_to admin_rd_station_integration_path, alert: "Conecte a RD Station e informe o segredo do webhook antes de sincronizar."
    end

    rd_client.register_webhooks!(url: webhooks_rd_station_url(token: @rd_station_setting.stored_webhook_secret))
    RdStationIntegrationSetting.save_webhook_status!(tenant: current_tenant, status: "ok", message: "Webhooks de conversão e oportunidade registrados.")
    redirect_to admin_rd_station_integration_path, notice: "Webhooks RD Station sincronizados."
  rescue StandardError => e
    RdStationIntegrationSetting.save_webhook_status!(tenant: current_tenant, status: "error", message: e.message)
    redirect_to admin_rd_station_integration_path, alert: e.message
  end

  def disconnect
    [
      RdStationIntegrationSetting::API_TOKEN_KEY,
      RdStationIntegrationSetting::REFRESH_TOKEN_KEY,
      RdStationIntegrationSetting::TOKEN_EXPIRES_AT_KEY,
      RdStationIntegrationSetting::WEBHOOK_STATUS_KEY,
      RdStationIntegrationSetting::WEBHOOK_MESSAGE_KEY
    ].each { |key| Setting.set(key, "", nil, tenant: current_tenant) }

    redirect_to admin_rd_station_integration_path, notice: "Conexão RD Station removida."
  end

  def update
    load_setting
    @rd_station_setting.assign_attributes(rd_station_params)

    if @rd_station_setting.save
      redirect_to admin_rd_station_integration_path, notice: "Configuração RD Station salva com sucesso."
    else
      flash.now[:alert] = "Revise os campos destacados antes de salvar."
      render :show, status: :unprocessable_content
    end
  end

  private

  def load_setting
    @rd_station_setting = RdStationIntegrationSetting.current(tenant: current_tenant)
    @rd_station_setting.ensure_webhook_secret!
  end

  def rd_station_params
    params.require(:rd_station).permit(
      :enabled,
      :client_id,
      :client_secret,
      :api_token,
      :default_business_type,
      :default_origin
    )
  end

  def rd_client
    @rd_client ||= RdStation::Client.new(setting: @rd_station_setting)
  end

  def callback_url
    callback_admin_rd_station_integration_url
  end
end
