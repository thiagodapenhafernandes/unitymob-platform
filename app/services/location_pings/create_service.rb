# frozen_string_literal: true

module LocationPings
  # Registra um ping de GPS para um check-in ativo.
  # Calcula inside_radius via PostGIS. Se ping está fora do raio:
  # - marca out_of_radius_since no check_in (se ainda não marcado)
  # - se já excedeu store.out_of_radius_tolerance_minutes, dispara auto-checkout
  #
  # Se ping volta para dentro do raio: limpa out_of_radius_since.
  #
  # Retorna:
  #   { success: true, ping: LocationPing, auto_checked_out: bool }
  #   { success: false, error:, message: }
  class CreateService
    ERRORS = {
      no_active_check_in:    "Nenhum check-in ativo.",
      missing_coordinates:   "Coordenadas não informadas.",
      invalid_coordinates:   "Coordenadas inválidas ou fora da faixa geográfica.",
      save_failed:           "Falha ao salvar ping."
    }.freeze

    def initialize(check_in:, lat:, lng:, accuracy: nil, battery_level: nil,
                   is_mock_location: false, ip: nil, user_agent: nil)
      @check_in = check_in
      @lat = lat
      @lng = lng
      @accuracy = accuracy
      @battery_level = battery_level
      @is_mock_location = is_mock_location
      @ip = ip
      @user_agent = user_agent
    end

    def call
      return fail_with(:no_active_check_in) unless @check_in&.active?
      return fail_with(:missing_coordinates) if @lat.blank? || @lng.blank?
      # Valida plausibilidade ANTES de tocar no PostGIS (contains?): lat/lng
      # fora da faixa faria o ST_Distance sobre geography levantar exceção.
      return fail_with(:invalid_coordinates) unless Geo::Coordinates.valid_point?(@lat, @lng)

      store = @check_in.store
      inside = store.contains?(@lat, @lng)

      ping = LocationPing.new(
        check_in: @check_in,
        admin_user_id: @check_in.admin_user_id,
        latitude: @lat,
        longitude: @lng,
        accuracy_meters: @accuracy&.to_i,
        battery_level: @battery_level&.to_f,
        # is_mock_location só é sinal quando o cliente reporta mock de fato
        # (true). Na web isso é indetectável (ver controller/analyzer): nil ou
        # false = DESCONHECIDO. A coluna é NOT NULL, então persistimos false,
        # mas o analyzer nunca trata isso como "limpo" — só true dispara flag.
        is_mock_location: @is_mock_location == true,
        inside_radius: inside,
        ip: @ip,
        user_agent: @user_agent,
        recorded_at: Time.current
      )
      return fail_with(:save_failed, ping.errors.full_messages.to_sentence) unless ping.save

      AntiFraud::AnalyzePingJob.perform_later(ping.id)

      auto_checked_out = update_radius_state!(ping)

      { success: true, ping: ping, auto_checked_out: auto_checked_out, inside_radius: inside }
    end

    private

    def update_radius_state!(ping)
      store = @check_in.store
      tolerance = store.out_of_radius_tolerance_minutes.to_i.minutes

      if ping.inside_radius
        # Voltou pro raio — limpa estado
        @check_in.update_column(:out_of_radius_since, nil) if @check_in.out_of_radius_since
        return false
      end

      # Fora do raio
      if @check_in.out_of_radius_since.blank?
        @check_in.update_column(:out_of_radius_since, ping.recorded_at)
        return false
      end

      # Já marcado — verifica se excedeu tolerância
      if Time.current - @check_in.out_of_radius_since >= tolerance
        CheckIns::CheckOutService.new(
          check_in: @check_in,
          reason: :closed_auto_out_of_radius,
          lat: ping.latitude,
          lng: ping.longitude,
          ip: ping.ip,
          accuracy: ping.accuracy_meters
        ).call
        return true
      end

      false
    end

    def fail_with(code, extra = nil)
      {
        success: false,
        error: code,
        message: [ERRORS[code], extra].compact.join(" — ")
      }
    end
  end
end
