module AntiFraud
  module CheckIns
    # Analisa um ping de localização e retorna sinais de suspeita.
    # Ruleset MVP (Fase 6), combinação de sinais fracos para reduzir falso positivo:
    #   1. Flag nativa is_mock_location (só quando o cliente reporta mock de
    #      fato; na web é indetectável — ver create_service/controller).
    #   2. Velocidade entre pings impossível (>200 km/h). Limitação: usa
    #      recorded_at do servidor e, além do par consecutivo, compara também
    #      contra a âncora do check-in (loja) para pegar teleporte no 1º ping.
    #   3. "GPS congelado": coordenada E accuracy byte-idênticas por vários
    #      pings seguidos (variância zero) — GPS real sempre tem jitter. Alta
    #      precisão sozinha NÃO é fraude (aparelhos dual-band reportam 3-5m).
    #   4. Fingerprint duplicado com outro admin_user (24h).
    #   5. ip_geo_mismatch (fraco): geo-IP vs GPS. Limitação: CGNAT/4G põe o
    #      geo-IP a centenas de km do usuário; nil = indeterminado, não "limpo".
    class Analyzer
      SPEED_THRESHOLD_KMH = 200.0
      # Sinal de "GPS congelado": exige coordenada E accuracy byte-idênticas
      # em toda a sequência (variância zero). Alta precisão por si só foi
      # removida como sinal — penalizava corretor honesto com aparelho bom.
      FROZEN_GPS_STREAK = 4
      FINGERPRINT_WINDOW = 24.hours
      IP_MISMATCH_THRESHOLD_KM = 500.0

      def self.analyze_ping(ping)
        new(ping).analyze
      end

      def initialize(ping)
        @ping = ping
        @check_in = ping.check_in
      end

      def analyze
        reasons = []

        reasons << "mock_location" if @ping.is_mock_location
        reasons << "impossible_speed" if impossible_speed?
        reasons << "frozen_gps_streak" if frozen_gps_streak?
        reasons << "duplicate_fingerprint" if duplicate_fingerprint?
        reasons << "ip_geo_mismatch" if ip_geo_mismatch?

        { suspicious: reasons.any?, reasons: reasons }
      end

      private

      # Velocidade impossível. Além do par de pings consecutivos, também
      # avalia a âncora do check-in (loja) → este ping, para pegar teleporte
      # já no 1º ping (ex.: check-in em SP, primeiro ping no RJ). LIMITAÇÃO:
      # recorded_at é o horário de chegada no servidor (não do device); um
      # cliente que atrasa o POST de um ponto distante dilui a velocidade
      # abaixo do limiar. Sinal fraco por design (MVP).
      def impossible_speed?
        speed_exceeded?(previous_ping) || speed_exceeded?(checkin_anchor)
      end

      def speed_exceeded?(origin)
        return false unless origin && origin[:latitude] && origin[:longitude] && origin[:at]
        return false unless @ping.latitude && @ping.longitude

        delta_seconds = (@ping.recorded_at - origin[:at]).to_f
        return false if delta_seconds <= 0

        distance_km = haversine_km(
          origin[:latitude], origin[:longitude],
          @ping.latitude, @ping.longitude
        )
        speed_kmh = distance_km / (delta_seconds / 3600.0)
        speed_kmh > SPEED_THRESHOLD_KMH
      end

      # Âncora do check-in (coordenada + horário do check-in), quando disponível.
      def checkin_anchor
        return nil unless @check_in.respond_to?(:checkin_latitude)

        at = @check_in.checked_in_at
        lat = @check_in.checkin_latitude
        lng = @check_in.checkin_longitude
        return nil unless at && lat && lng

        { latitude: lat, longitude: lng, at: at }
      end

      # "GPS congelado": coordenada E accuracy byte-idênticas ao longo de vários
      # pings seguidos. GPS real tem jitter mesmo parado, então variância ZERO
      # é o sinal artificial — não "alta precisão" (que aparelho bom entrega).
      def frozen_gps_streak?
        return false unless @ping.latitude && @ping.longitude

        recent = @check_in.location_pings
          .where("recorded_at <= ?", @ping.recorded_at)
          .order(recorded_at: :desc)
          .limit(FROZEN_GPS_STREAK)
          .to_a
        return false if recent.size < FROZEN_GPS_STREAK

        recent.all? do |p|
          p.latitude == @ping.latitude &&
            p.longitude == @ping.longitude &&
            p.accuracy_meters == @ping.accuracy_meters
        end
      end

      def duplicate_fingerprint?
        fp = @check_in.fingerprint_hash
        return false if fp.blank?

        @check_in.tenant.check_ins.where(fingerprint_hash: fp)
               .where.not(admin_user_id: @check_in.admin_user_id)
               .where("checked_in_at >= ?", FINGERPRINT_WINDOW.ago)
               .exists?
      end

      # LIMITAÇÃO (sinal fraco): limiar de 500 km é grande e o geo-IP em redes
      # móveis (CGNAT/4G) aponta para o POP da operadora, a centenas de km do
      # usuário — por isso mantemos o limiar conservador para não gerar falso
      # positivo. geo nil (IP privado/erro/base ausente) = INDETERMINADO, não
      # "limpo": simplesmente não contribui (fail-open, sem flag). Não roda no
      # check-in inicial, só nos pings.
      def ip_geo_mismatch?
        return false if @ping.ip.blank? || @ping.latitude.nil? || @ping.longitude.nil?

        geo = AntiFraud::GeoIpResolver.lookup(@ping.ip.to_s)
        return false unless geo && geo[:latitude] && geo[:longitude]

        distance_km = haversine_km(
          @ping.latitude, @ping.longitude,
          geo[:latitude], geo[:longitude]
        )
        distance_km > IP_MISMATCH_THRESHOLD_KM
      end

      # Origem do ping imediatamente anterior, normalizada no mesmo formato da
      # âncora ({latitude:, longitude:, at:}) para speed_exceeded?. latitude/
      # longitude são attr_accessor populados por after_find, então precisamos
      # do registro carregado (não pluck da coluna geography).
      def previous_ping
        record = @check_in.location_pings
          .where("recorded_at < ?", @ping.recorded_at)
          .order(recorded_at: :desc)
          .first
        return nil unless record && record.latitude && record.longitude

        { latitude: record.latitude, longitude: record.longitude, at: record.recorded_at }
      end

      # Haversine — distância em km entre dois pontos (lat/lng em graus).
      def haversine_km(lat1, lng1, lat2, lng2)
        r = 6371.0
        phi1 = lat1 * Math::PI / 180
        phi2 = lat2 * Math::PI / 180
        dphi = (lat2 - lat1) * Math::PI / 180
        dlambda = (lng2 - lng1) * Math::PI / 180

        a = Math.sin(dphi / 2)**2 + Math.cos(phi1) * Math.cos(phi2) * Math.sin(dlambda / 2)**2
        c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        r * c
      end
    end
  end
end
