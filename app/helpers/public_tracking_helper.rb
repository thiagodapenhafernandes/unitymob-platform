module PublicTrackingHelper
  def public_tracking_page_context
    property = @habitation if controller_name == 'habitations' && action_name == 'show'
    type = property&.whatsapp_negotiation_type || params[:business_type].presence || params[:transaction_type].presence || 'general'
    type = { 'aluguel' => 'rent', 'locação' => 'rent' }.fetch(type.to_s.downcase, type)
    type = 'diaria' if property&.daily_rental?
    type = 'general' unless type.in?(%w[sale rent rental sale_rent general venda locacao diaria])
    type = Leads::Attribution.business_type(type)
    page_type = if property
      'property'
    elsif controller_name.in?(%w[habitations empreendimentos]) && action_name == 'index'
      'listing'
    elsif controller_name == 'home' && action_name == 'index'
      'home'
    elsif controller_name == 'blog'
      'blog'
    elsif controller_name.in?(%w[pages home])
      'institutional'
    else
      'other'
    end
    context = { business_type: type, page_type: page_type, site_language: 'pt-br' }
    if property
      property_context = Tracking::EventContext.property(property, business_type: type)
      context.merge!(property_context)
      context[:ecommerce] = Tracking::EventContext.ecommerce(property_context, business_type: type)
    elsif page_type == 'listing' && defined?(@habitations) && @habitations
      context[:results_count] = @habitations.respond_to?(:total_entries) ? @habitations.total_entries : @habitations.size
      context[:search_filters] = {
        property_type: params[:category], city: params[:city], neighborhood: params[:neighborhood],
        bedrooms_min: params[:min_bedrooms], price_min: params[:min_price], price_max: params[:max_price]
      }.compact_blank
      %i[bedrooms_min price_min price_max].each do |key|
        value = context[:search_filters][key]
        next unless value
        if value.to_s.match?(/\A\d+(?:\.\d+)?\z/)
          context[:search_filters][key] = value.to_f
        else
          context[:search_filters].delete(key)
        end
      end
    end
    context.compact_blank
  end
end
