class Admin::GoogleIntegrationsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :integracoes) }

  def show
    @google_sheets_setting = GoogleSheetsIntegrationSetting.current
  end

  def update
    @google_sheets_setting = GoogleSheetsIntegrationSetting.current
    @google_sheets_setting.assign_attributes(google_sheets_params)

    if @google_sheets_setting.save
      redirect_to admin_google_integration_path, notice: "Configurações do Google Sheets salvas com sucesso."
    else
      flash.now[:alert] = "Revise os campos destacados antes de salvar."
      render :show, status: :unprocessable_content
    end
  end

  private

  def google_sheets_params
    params.require(:google_sheets).permit(:enabled, :web_app_url, :token, :worksheet_name, :key_column)
  end
end
