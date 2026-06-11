# frozen_string_literal: true

module Field
  class CheckInsController < BaseController
    before_action :ensure_field_enabled!
    before_action :ensure_field_agent!
    before_action :set_active_check_in, only: [:check_out]

    # GET /field/check_ins/new — tela do fluxo GPS → check-in
    def new
      @active_check_in = current_admin_user.active_check_in
    end

    # POST /field/check_ins
    # Params esperados: lat, lng, accuracy, device_info (JSON)
    def create
      result = CheckIns::CreateService.new(
        admin_user: current_admin_user,
        lat: params[:lat],
        lng: params[:lng],
        accuracy: params[:accuracy],
        ip: request.remote_ip,
        device_info: device_info_from_params,
        fingerprint_hash: params[:fingerprint_hash].to_s.presence
      ).call

      if result[:success]
        render json: {
          ok: true,
          check_in_id: result[:check_in].id,
          store_name: result[:check_in].store.name,
          distance_meters: result[:distance_meters].to_i
        }, status: :created
      else
        render json: { ok: false, error: result[:error], message: result[:message] }, status: :unprocessable_entity
      end
    end

    # PATCH /field/check_ins/:id/check_out
    def check_out
      result = CheckIns::CheckOutService.new(
        check_in: @active_check_in,
        reason: :closed_manual,
        lat: params[:lat],
        lng: params[:lng],
        accuracy: params[:accuracy],
        ip: request.remote_ip
      ).call

      if result[:success]
        render json: { ok: true, check_in_id: result[:check_in].id, duration_seconds: result[:check_in].duration.to_i }
      else
        render json: { ok: false, error: result[:error], message: result[:message] }, status: :unprocessable_entity
      end
    end

    private

    def set_active_check_in
      @active_check_in = current_admin_user.active_check_in
      if @active_check_in.nil? || @active_check_in.id != params[:id].to_i
        render json: { ok: false, error: "no_active_check_in" }, status: :not_found
      end
    end

    def device_info_from_params
      raw = params[:device_info]
      return {} if raw.blank?
      return raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
      JSON.parse(raw)
    rescue JSON::ParserError
      {}
    end
  end
end
