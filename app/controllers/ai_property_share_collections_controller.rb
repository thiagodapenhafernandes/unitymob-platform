class AiPropertyShareCollectionsController < ApplicationController
  IDENTITY_COOKIE = :ai_property_interest_identity

  def show
    load_collection
    @habitations = @collection.habitations.active.includes(:address)
    @collection.record!("collection_opened", metadata: request_metadata)
  end

  def interest
    load_collection
    habitation = @collection.habitations.active.find(params[:habitation_id])
    lead = recognized_lead || identify_lead
    return render json: { requires_identity: true }, status: :unprocessable_entity unless lead

    interest = lead.property_interests.find_or_create_by!(tenant: @collection.tenant, habitation:)
    responsible = lead.admin_user || @collection.admin_user
    lead.update!(admin_user: responsible) if lead.admin_user.blank?
    remember(lead)
    event = interest.previously_new_record? ? "interest_created" : "interest_repeated"
    @collection.record!(event, lead:, habitation:, admin_user: responsible, metadata: request_metadata.merge(shared_by_admin_user_id: @collection.admin_user_id))
    LeadActivity.log!(lead:, kind: "property_interest", metadata: { habitation_id: habitation.id, share_collection_id: @collection.id, event: })

    render json: { success: true, message: @setting.ai_property_search_interest_success_message, lead_id: lead.id }
  end

  private

  def load_collection
    @collection = AiPropertyShareCollection.active.find_by!(token: params[:token])
    Current.tenant = @collection.tenant
    @setting = PropertySetting.instance(tenant: @collection.tenant)
    raise ActiveRecord::RecordNotFound unless @setting.ai_property_search_sharing_enabled?
  end

  def recognized_lead
    data = cookies.signed[IDENTITY_COOKIE]
    return unless data.is_a?(Hash) && data["tenant_id"].to_i == @collection.tenant_id
    @collection.tenant.leads.find_by(id: data["lead_id"])
  end

  def identify_lead
    name = params[:name].to_s.strip
    phone = Phones::Normalizer.call(params[:phone]).to_s
    return if name.blank? || phone.blank?

    lead = @collection.tenant.leads.where("phone = :phone OR client_phone = :phone", phone:).first
    if lead
      @collection.record!("visitor_matched_existing_lead", lead:, admin_user: lead.admin_user, metadata: request_metadata.merge(shared_by_admin_user_id: @collection.admin_user_id))
      lead
    else
      lead = @collection.tenant.leads.create!(name:, phone:, admin_user: @collection.admin_user, shared_by_admin_user: @collection.admin_user, origin: @setting.ai_property_search_lead_origin, status: Lead.status_value(:novo, tenant: @collection.tenant))
      @collection.record!("lead_created_from_interest", lead:, admin_user: @collection.admin_user, metadata: request_metadata)
      lead
    end
  end

  def remember(lead)
    cookies.signed[IDENTITY_COOKIE] = { value: { tenant_id: lead.tenant_id, lead_id: lead.id }, expires: @setting.ai_property_search_visitor_recognition_days.days.from_now, httponly: true, same_site: :lax }
  end

  def request_metadata
    { ip: request.remote_ip, user_agent: request.user_agent.to_s.first(300) }
  end
end
