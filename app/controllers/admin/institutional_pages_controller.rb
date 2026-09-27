# Conteúdo das páginas institucionais do site público: página Sobre (missão,
# visão, valores) e Links úteis. Grava no mesmo PublicSiteProfile do Perfil
# público, só nos campos desta tela.
class Admin::InstitutionalPagesController < Admin::BaseController
  requires_permission :manage, :site_publico

  def edit
    @profile = PublicSiteProfile.current(tenant: current_tenant)
  end

  def update
    @profile = PublicSiteProfile.current(tenant: current_tenant)
    @profile.assign_attributes(params.require(:public_site_profile).permit(:institutional_mission, :institutional_vision, :institutional_values))
    # Sem nenhuma linha o navegador não envia o campo: atribui vazio para limpar.
    @profile.useful_link_rows = params.fetch(:public_site_profile, {})
      .permit(useful_link_rows: %i[label url description icon])[:useful_link_rows]&.to_h || {}

    if @profile.save
      redirect_to edit_admin_institutional_page_path, notice: "Páginas institucionais atualizadas."
    else
      render :edit, status: :unprocessable_entity
    end
  end
end
