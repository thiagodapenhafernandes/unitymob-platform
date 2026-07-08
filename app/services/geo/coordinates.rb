module Geo
  # Validação de plausibilidade de coordenadas no servidor: lat/lng presentes,
  # numéricos e dentro da faixa geográfica válida. Usado no check-in e nos pings
  # para rejeitar entrada malformada / lat-lng trocados antes de gravar geografia.
  module Coordinates
    LAT_RANGE = (-90.0..90.0)
    LNG_RANGE = (-180.0..180.0)

    module_function

    def parse(value)
      Float(value, exception: false)
    end

    # true quando o par é um ponto geográfico plausível.
    def valid_point?(lat, lng)
      flat = parse(lat)
      flng = parse(lng)
      return false if flat.nil? || flng.nil?

      LAT_RANGE.cover?(flat) && LNG_RANGE.cover?(flng)
    end
  end
end
