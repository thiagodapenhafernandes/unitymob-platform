class Admin::CommercialContractTermsVersionsController < Admin::BaseController
  before_action :require_admin_or_administrative_user!
  before_action :set_terms_version, only: [:show, :edit, :update]

  def index
    CommercialContractTermsVersion.current_for(current_tenant)
    @terms_versions = current_tenant.commercial_contract_terms_versions.ordered
  end

  def show; end

  def new
    current = CommercialContractTermsVersion.current_for(current_tenant)
    @terms_version = current_tenant.commercial_contract_terms_versions.new(
      version: Time.current.strftime("%Y.%m.%d"),
      title: current.title,
      body: current.body,
      active: true
    )
  end

  def create
    @terms_version = current_tenant.commercial_contract_terms_versions.new(terms_params)
    @terms_version.published_at ||= Time.current

    if @terms_version.save
      redirect_to admin_commercial_contract_terms_version_path(@terms_version), notice: "Versão dos termos publicada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @terms_version.commercial_contract_proposals.exists?
      redirect_to admin_commercial_contract_terms_version_path(@terms_version), alert: "Versão já usada em proposta. Publique uma nova versão para alterar o texto."
    elsif @terms_version.update(terms_params)
      redirect_to admin_commercial_contract_terms_version_path(@terms_version), notice: "Termos atualizados."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_terms_version
    @terms_version = current_tenant.commercial_contract_terms_versions.find(params[:id])
  end

  def terms_params
    params.require(:commercial_contract_terms_version).permit(:version, :title, :body, :active)
  end
end
