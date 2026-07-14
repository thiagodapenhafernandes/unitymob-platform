class Admin::PublicSiteProfilesController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }

  def edit
    @profile = PublicSiteProfile.current(tenant: current_tenant)
  end

  def update
    @profile = PublicSiteProfile.new(profile_params, tenant: current_tenant)
    if @profile.save
      redirect_to edit_admin_public_site_profile_path, notice: "Perfil do site público atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:public_site_profile).permit(*PublicSiteProfile::FIELDS)
  end
end
