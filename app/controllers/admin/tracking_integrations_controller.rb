class Admin::TrackingIntegrationsController < Admin::BaseController
  before_action :require_system_admin!
  before_action -> { check_permission!(:manage, :integracoes) }

  def show
    @tracking_setting = TrackingIntegrationSetting.current
    @active_tab = active_tab
  end

  def update
    @tracking_setting = TrackingIntegrationSetting.current
    @tracking_setting.assign_attributes(tracking_params)
    @active_tab = active_tab

    if @tracking_setting.save
      redirect_to admin_tracking_integration_path(tab: @active_tab), notice: "Configurações de trackeamento salvas com sucesso."
    else
      flash.now[:alert] = "Revise os campos destacados antes de salvar."
      render :show, status: :unprocessable_content
    end
  end

  private

  def tracking_params
    params.require(:tracking).permit(
      :google_tag_manager_enabled,
      :google_tag_manager_container_id,
      :meta_pixel_enabled,
      :meta_pixel_id
    )
  end

  def active_tab
    params[:tab].presence_in(%w[google_tag_manager meta_pixel]) || "google_tag_manager"
  end
end
