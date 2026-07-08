class Admin::GoogleIntegrationsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :integracoes) }

  def show
    load_google_settings
    @active_tab = params[:tab].presence_in(%w[sheets calendar]) || "sheets"
  end

  def update
    load_google_settings

    if params[:google_calendar].present?
      update_google_calendar
    else
      update_google_sheets
    end
  end

  def test_calendar
    load_google_settings
    event = GoogleCalendar::TestEventCreator.new(setting: @google_calendar_setting, tenant: current_tenant).call
    redirect_to admin_google_integration_path(tab: "calendar"),
                notice: "Evento de teste criado na Agenda Google: #{event.id}."
  rescue StandardError => e
    redirect_to admin_google_integration_path(tab: "calendar"),
                alert: "Não foi possível criar o evento de teste: #{e.message}"
  end

  private

  def load_google_settings
    @google_sheets_setting = GoogleSheetsIntegrationSetting.current
    @google_calendar_setting = GoogleCalendarIntegrationSetting.for(current_tenant)
  end

  def update_google_sheets
    @google_sheets_setting.assign_attributes(google_sheets_params)

    if @google_sheets_setting.save
      redirect_to admin_google_integration_path(tab: "sheets"), notice: "Configurações do Google Sheets salvas com sucesso."
    else
      @active_tab = "sheets"
      flash.now[:alert] = "Revise os campos destacados antes de salvar."
      render :show, status: :unprocessable_content
    end
  end

  def update_google_calendar
    @google_calendar_setting.assign_attributes(google_calendar_params.except(:service_account_json))
    service_account_json = google_calendar_params[:service_account_json].to_s.strip
    @google_calendar_setting.service_account_json = service_account_json if service_account_json.present?

    if @google_calendar_setting.save
      redirect_to admin_google_integration_path(tab: "calendar"), notice: "Configurações da Agenda Google salvas com sucesso."
    else
      @active_tab = "calendar"
      flash.now[:alert] = "Revise os campos destacados antes de salvar."
      render :show, status: :unprocessable_content
    end
  end

  def google_sheets_params
    params.require(:google_sheets).permit(:enabled, :web_app_url, :token, :worksheet_name, :key_column)
  end

  def google_calendar_params
    params.require(:google_calendar).permit(:enabled, :calendar_id, :default_duration_minutes, :service_account_json)
  end
end
