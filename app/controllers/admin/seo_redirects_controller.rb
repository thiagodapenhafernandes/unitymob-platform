class Admin::SeoRedirectsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }
  before_action :set_redirect, only: [:update, :destroy]

  def index
    @seo_redirect = current_tenant.seo_redirects.new(status_code: 301, active: true)
    @seo_redirects = current_tenant.seo_redirects.recent.paginate(page: params[:page], per_page: 25)
  end

  def create
    @seo_redirect = current_tenant.seo_redirects.new(redirect_params)
    @seo_redirect.created_by_admin_user = current_admin_user

    if @seo_redirect.save
      redirect_to admin_seo_redirects_path, notice: "Redirect criado."
    else
      @seo_redirects = current_tenant.seo_redirects.recent.paginate(page: params[:page], per_page: 25)
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @seo_redirect.update(redirect_params)
      redirect_to admin_seo_redirects_path, notice: "Redirect atualizado."
    else
      @seo_redirects = current_tenant.seo_redirects.recent.paginate(page: params[:page], per_page: 25)
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @seo_redirect.destroy
    redirect_to admin_seo_redirects_path, notice: "Redirect removido."
  end

  private

  def set_redirect
    @seo_redirect = current_tenant.seo_redirects.find(params[:id])
  end

  def redirect_params
    params.require(:seo_redirect).permit(:from_path, :to_path, :status_code, :active)
  end
end
