module Field
  class PropertyShareCollectionsController < BaseController
    before_action :authorize_ai_property_search!

    def create
      setting = PropertySetting.instance(tenant: current_tenant)
      return render json: { error: setting.ai_property_search_sharing_disabled_message }, status: :forbidden unless setting.ai_property_search_sharing_enabled?

      ids = Array(params[:habitation_ids]).first(setting.ai_property_search_share_max_properties)
      result = Ai::PropertyShareCollectionCreator.call(
        tenant: current_tenant,
        admin_user: current_admin_user,
        setting:,
        scope: current_tenant.habitations.active.where(id: ids),
        source: "field_property_search"
      )
      record_user_activity!(
        "selection_shared",
        result_count: result.habitations.size,
        visible_habitation_ids: result.habitations.map(&:id),
        metadata: { source: "field_property_search", requested_count: ids.size }
      )

      render json: {
        url: ai_property_share_collection_url(result.collection.token),
        count: result.habitations.size,
        share_title: setting.ai_property_search_share_title,
        share_message: setting.ai_property_search_message(:ai_property_search_share_message, count: result.habitations.size)
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
