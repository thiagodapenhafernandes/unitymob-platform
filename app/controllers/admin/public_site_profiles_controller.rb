class Admin::PublicSiteProfilesController < Admin::BaseController
  requires_permission :manage, :site_publico

  # Conteúdo das páginas (Sobre, Links úteis) fica em Páginas institucionais.
  EDITABLE_FIELDS = %i[
    primary_city legal_name legal_document legal_address privacy_email creci
    show_development_identity custom_price_ranges
  ].freeze

  def edit
    load_profile
  end

  def update
    load_profile
    @profile.assign_attributes(profile_params)
    # Sem nenhuma linha o navegador não envia o campo: atribui vazio para limpar.
    @profile.sale_price_rows = price_rows_param(:sale_price_rows)
    @profile.rental_price_rows = price_rows_param(:rental_price_rows)

    if @profile.save
      Rails.cache.delete(PublicSite::PriceRanges.cache_key(current_tenant.id))
      redirect_to edit_admin_public_site_profile_path, notice: "Perfil do site público atualizado."
    else
      load_form_context
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def load_profile
    @profile = PublicSiteProfile.current(tenant: current_tenant)
    load_form_context
  end

  def load_form_context
    @automatic_price_ranges = PublicSite::PriceRanges.for(current_tenant)
    city_groups = current_tenant.habitations.public_city_link_groups(cities: 30, neighborhoods: 0)
    @city_suggestions = city_groups.map { |group| group[:label] }
    @automatic_city = city_groups.first&.dig(:label)
  end

  def profile_params
    params.require(:public_site_profile).permit(*EDITABLE_FIELDS)
  end

  def price_rows_param(key)
    params.fetch(:public_site_profile, {}).permit(key => %i[label min max])[key]&.to_h || {}
  end
end
