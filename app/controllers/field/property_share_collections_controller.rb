module Field
  class PropertyShareCollectionsController < BaseController
    before_action :authorize_ai_property_search!

    def create
      setting = PropertySetting.instance(tenant: current_tenant)
      return render json: { error: setting.ai_property_search_sharing_disabled_message }, status: :forbidden unless setting.ai_property_search_sharing_enabled?

      habitations = current_tenant.habitations.active.where(id: Array(params[:habitation_ids]).first(setting.ai_property_search_share_max_properties))
      raise ActiveRecord::RecordNotFound if habitations.empty?

      collection = current_tenant.ai_property_share_collections.create!(admin_user: current_admin_user)
      habitations.each { |habitation| collection.items.create!(habitation:) }
      collection.record!("collection_created", admin_user: current_admin_user, metadata: { habitation_ids: habitations.ids })

      render json: {
        url: ai_property_share_collection_url(collection.token),
        count: habitations.size,
        share_title: setting.ai_property_search_share_title,
        share_message: setting.ai_property_search_message(:ai_property_search_share_message, count: habitations.size)
      }
    end

    private

    def authorize_ai_property_search!
      setting = PropertySetting.instance(tenant: current_tenant)
      return if setting.ai_property_search_available_to?(current_admin_user)

      render json: { error: "Busca inteligente indisponível para seu perfil." }, status: :forbidden
    end
  end
end
