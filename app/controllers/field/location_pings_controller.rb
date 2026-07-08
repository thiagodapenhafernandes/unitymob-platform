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

      # Não confia cegamente nos params do cliente: valida plausibilidade das
      # coordenadas na borda antes de acionar o service (o LocationPing revalida
      # a mesma faixa no servidor).
      unless Geo::Coordinates.valid_point?(params[:lat], params[:lng])
        render json: { ok: false, error: "invalid_coordinates", message: "Coordenadas inválidas." },
               status: :unprocessable_entity
        return
      end

      result = LocationPings::CreateService.new(
        check_in: check_in,
        lat: params[:lat],
        lng: params[:lng],
        accuracy: params[:accuracy],
        battery_level: params[:battery_level],
        is_mock_location: mock_location_param,
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

    private

    # A plataforma web (navigator.geolocation) NÃO expõe a flag nativa de mock
    # do Android — só apps nativos conseguem lê-la. Portanto o valor vindo do
    # cliente é indetectável/forjável: só o tratamos como sinal quando é
    # explicitamente truthy; ausente/false vira nil (DESCONHECIDO), não "limpo".
    def mock_location_param
      raw = params[:is_mock_location]
      return nil if raw.nil?

      cast = ActiveModel::Type::Boolean.new.cast(raw)
      cast == true ? true : nil
    end
  end
end
