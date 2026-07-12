class LandingPagesController < ApplicationController
  def show
    @landing_page = public_tenant.landing_pages.find_by!(slug: params[:slug], active: true)
    
    # The filter_params are stored as a JSON hash in the database
    filters = @landing_page.filter_params || {}
    
    # Use the robust advanced_search scope
    # We map keys to match what advanced_search expects if needed
    search_params = {
      category: filters['category'],
      city: filters['city'],
      neighborhood: filters['neighborhood'],
      transaction_type: filters['transaction_type'],
      min_bedrooms: filters['min_bedrooms'],
      min_suites: filters['min_suites'],
      min_parking: filters['min_parking'],
      target_price: filters['target_price'],
      min_area: filters['min_area'],
      opportunity: filters['opportunity'],
      characteristics: filters['characteristics'],
      caracteristica_unica: filters['caracteristica_unica'],
      status: filters['status'],
      sort: params[:sort].presence || filters['sort']
    }

    @habitations = public_habitations
      .active
      .advanced_search(search_params)
      .includes(
        :address,
        { constructor: { logo_attachment: :blob } },
        { empreendimento: { constructor: { logo_attachment: :blob } } }
      )
      .paginate(page: params[:page], per_page: 12)
    PublicSite::CardPhotoPreloader.new(@habitations.to_a, limit: 5).call
    
    # SEO meta tags
    @page_title = @landing_page.meta_title.presence || @landing_page.title
    @meta_description = @landing_page.meta_description
  end
end
