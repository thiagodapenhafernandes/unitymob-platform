class Admin::LoversIntegrationsController < Admin::BaseController
  requires_permission :manage, :integracoes

  def show
    load_setting
  end

  def update
    load_setting
    @lovers_setting.assign_attributes(lovers_params)

    if @lovers_setting.save
      redirect_to admin_lovers_integration_path, notice: "Configuração Lovers salva com sucesso."
    else
      flash.now[:alert] = "Revise os campos destacados antes de salvar."
      render :show, status: :unprocessable_content
    end
  end

  def test_connection
    load_setting
    unless @lovers_setting.api_token_configured?
      return redirect_to admin_lovers_integration_path, alert: "Informe o token da API antes de testar a conexão."
    end

    user = lovers_client.user
    LoversIntegrationSetting.save_sync_status!(tenant: current_tenant, status: "ok", message: "Conexão validada para #{user['UserName'].presence || user['UserEmail'].presence || 'usuário Lovers'}.")
    redirect_to admin_lovers_integration_path, notice: "Conexão Lovers validada."
  rescue StandardError => e
    LoversIntegrationSetting.save_sync_status!(tenant: current_tenant, status: "error", message: e.message)
    redirect_to admin_lovers_integration_path, alert: e.message
  end

  def sync_now
    load_setting
    unless @lovers_setting.configured?
      return redirect_to admin_lovers_integration_path, alert: "Ative a integração e informe o token da API antes de sincronizar."
    end

    result = Lovers::LeadSync.call(setting: @lovers_setting)
    LoversIntegrationSetting.save_sync_status!(tenant: current_tenant, status: "ok", message: result.message)
    redirect_to admin_lovers_integration_path, notice: result.message
  rescue StandardError => e
    LoversIntegrationSetting.save_sync_status!(tenant: current_tenant, status: "error", message: e.message)
    redirect_to admin_lovers_integration_path, alert: e.message
  end

  def disconnect
    LoversIntegrationSetting.clear_connection!(tenant: current_tenant)
    redirect_to admin_lovers_integration_path, notice: "Conexão Lovers removida."
  end

  private

  def load_setting
    @lovers_setting = LoversIntegrationSetting.current(tenant: current_tenant)
  end

  def lovers_params
    params.require(:lovers).permit(:enabled, :api_token, :default_origin, :sync_start_date)
  end

  def lovers_client
    Lovers::Client.new(token: @lovers_setting.stored_api_token)
  end
end
