class Admin::GoogleIntegrationsController < Admin::BaseController
  requires_permission :manage, :integracoes

  def show
    load_google_settings
    @active_tab = params[:tab].presence_in(%w[sheets calendar maps ga4]) || "sheets"
    @active_tab = "sheets" if @active_tab == "ga4" && @ga4_config.nil?
  end

  def update
    return update_ga4 if params[:ga4].present?

    load_google_settings

    if params[:google_maps].present?
      update_google_maps
    elsif params[:google_calendar].present?
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
    @ga4_config = Ga4ConversionConfig.find_or_initialize_by(tenant_id: current_tenant.id) if tenant_owner?
    @google_sheets_setting = GoogleSheetsIntegrationSetting.current(tenant: current_tenant)
    @google_calendar_setting = GoogleCalendarIntegrationSetting.for(current_tenant)
    @google_maps_setting = GoogleMapsIntegrationSetting.for(current_tenant)
  end

  def update_ga4
    config = Ga4ConversionConfig.find_or_initialize_by(tenant_id: current_tenant.id) if tenant_owner?
    return head :not_found unless config

    permitted = params.require(:ga4).permit(:reporting_enabled, :reporting_property_id, :reporting_credentials)
    config.reporting_enabled = ActiveModel::Type::Boolean.new.cast(permitted[:reporting_enabled]) || false if permitted.key?(:reporting_enabled)
    config.reporting_property_id = permitted[:reporting_property_id].to_s.strip if permitted.key?(:reporting_property_id)
    config.reporting_credentials = permitted[:reporting_credentials].to_s.strip if permitted[:reporting_credentials].present?
    if config.save
      redirect_to admin_google_integration_path(tab: "ga4"), notice: "Conexão de leitura do GA4 salva. O painel consultará os relatórios automaticamente."
    else
      load_google_settings
      @ga4_config = config
      @active_tab = "ga4"
      flash.now[:alert] = "Revise a conexão de leitura do GA4."
      render :show, status: :unprocessable_content
    end
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

  def update_google_maps
    @google_maps_setting.assign_attributes(google_maps_params.except(:api_key))
    api_key = google_maps_params[:api_key].to_s.strip
    @google_maps_setting.api_key = api_key if api_key.present?

    if @google_maps_setting.save
      redirect_to admin_google_integration_path(tab: "maps"), notice: "Configurações do mapa salvas com sucesso."
    else
      @active_tab = "maps"
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

  def google_maps_params
    params.require(:google_maps).permit(
      :enabled,
      :provider,
      :api_key,
      :default_display_mode,
      :approximate_radius_meters,
      :default_zoom,
      :satellite_enabled,
      :street_view_enabled,
      :external_link_enabled
    )
  end
end
