module AntiFraud
  module CheckIns
    # Analisa um ping de localização e retorna sinais de suspeita.
    # Ruleset MVP (Fase 6), combinação de sinais fracos para reduzir falso positivo:
    #   1. Flag nativa is_mock_location do Android (device reportou mock)
    #   2. Velocidade entre pings impossível (>200 km/h)
    #   3. Precisão "perfeita demais" por >3 pings consecutivos (<5m, típico de spoof)
    #   4. Fingerprint duplicado com outro admin_user (24h)
    class Analyzer
      SPEED_THRESHOLD_KMH = 200.0
      SUSPICIOUS_ACCURACY_STREAK = 3
      SUSPICIOUS_ACCURACY_THRESHOLD = 5
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
        reasons << "suspicious_accuracy_streak" if suspicious_accuracy_streak?
        reasons << "duplicate_fingerprint" if duplicate_fingerprint?
        reasons << "ip_geo_mismatch" if ip_geo_mismatch?

        { suspicious: reasons.any?, reasons: reasons }
      end

      private

      def impossible_speed?
        previous = previous_ping
        return false unless previous && previous.latitude && previous.longitude && @ping.latitude && @ping.longitude

        delta_seconds = (@ping.recorded_at - previous.recorded_at).to_f
        return false if delta_seconds <= 0

        distance_km = haversine_km(
          previous.latitude, previous.longitude,
          @ping.latitude, @ping.longitude
        )
        speed_kmh = distance_km / (delta_seconds / 3600.0)
        speed_kmh > SPEED_THRESHOLD_KMH
      end

      def suspicious_accuracy_streak?
        return false unless @ping.accuracy_meters && @ping.accuracy_meters < SUSPICIOUS_ACCURACY_THRESHOLD

        recent_streak = @check_in.location_pings
          .where("recorded_at <= ?", @ping.recorded_at)
          .order(recorded_at: :desc)
          .limit(SUSPICIOUS_ACCURACY_STREAK)
          .pluck(:accuracy_meters)

        recent_streak.size >= SUSPICIOUS_ACCURACY_STREAK &&
          recent_streak.all? { |a| a && a < SUSPICIOUS_ACCURACY_THRESHOLD }
      end

      def duplicate_fingerprint?
        fp = @check_in.fingerprint_hash
        return false if fp.blank?

        CheckIn.where(fingerprint_hash: fp)
               .where.not(admin_user_id: @check_in.admin_user_id)
               .where("checked_in_at >= ?", FINGERPRINT_WINDOW.ago)
               .exists?
      end

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

      def previous_ping
        @check_in.location_pings
          .where("recorded_at < ?", @ping.recorded_at)
          .order(recorded_at: :desc)
          .first
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
