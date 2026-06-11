# frozen_string_literal: true

module Field
  class LocationPingsController < BaseController
    before_action :ensure_field_enabled!
    before_action :ensure_field_agent!

    # POST /field/location_pings
    # Payload JSON: { lat, lng, accuracy, battery_level, is_mock_location }
    def create
      check_in = current_admin_user.active_check_in
      unless check_in
        render json: { ok: false, error: "no_active_check_in" }, status: :not_found
        return
      end

      result = LocationPings::CreateService.new(
        check_in: check_in,
        lat: params[:lat],
        lng: params[:lng],
        accuracy: params[:accuracy],
        battery_level: params[:battery_level],
        is_mock_location: ActiveModel::Type::Boolean.new.cast(params[:is_mock_location]),
        ip: request.remote_ip,
        user_agent: request.user_agent
      ).call

      if result[:success]
        render json: {
          ok: true,
          inside_radius: result[:inside_radius],
          auto_checked_out: result[:auto_checked_out]
        }
      else
        render json: { ok: false, error: result[:error], message: result[:message] }, status: :unprocessable_entity
      end
    end
  end
end
