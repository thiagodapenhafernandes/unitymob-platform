# frozen_string_literal: true

module CheckIns
  # Cria um CheckIn após validar:
  # - feature flag ligada
  # - usuário ativo sem bloqueio pontual de check-in
  # - sem check-in ativo
  # - coordenadas plausíveis (faixa geográfica válida — Geo::Coordinates)
  # - accuracy aceitável e presente (<= 50m; obrigatória p/ check-in por GPS)
  # - loja resolvida dentro do raio
  # - turno ativo naquela loja agora
  #
  # Antifraude no instante do check-in: extrai os sinais do device
  # (is_mock_location, accuracy) para o device_info e, quando o device
  # reporta mock location, marca o check-in como suspeito + audita — SEM
  # bloquear (a decisão de bloquear vs. só registrar é de produto; hoje
  # registramos para não reprovar corretor legítimo).
  #
  # Retorna:
  #   { success: true, check_in: CheckIn } em caso de sucesso
  #   { success: false, error: Symbol, message: String } em caso de erro
  class CreateService
    MAX_ACCURACY_METERS = 50

    # Chaves aceitas para o sinal nativo de mock location vindo do device.
    MOCK_LOCATION_KEYS = %w[is_mock_location mock_location isMock mock].freeze

    ERRORS = {
      feature_disabled:      "Feature de check-in não está habilitada.",
      not_field_agent:       "Check-in indisponível para sua operação.",
      already_active:        "Você já tem um check-in ativo. Faça check-out antes.",
      invalid_accuracy:      "Sinal de GPS muito fraco. Tente novamente em local aberto.",
      invalid_coordinates:   "Coordenadas GPS inválidas.",
      no_store_in_range:     "Nenhuma loja encontrada no seu raio.",
      no_active_shift:       "Você não tem turno ativo nesta loja neste horário.",
      missing_coordinates:   "Coordenadas GPS não fornecidas.",
      save_failed:           "Falha ao salvar o check-in."
    }.freeze

    def initialize(admin_user:, lat:, lng:, accuracy: nil, ip: nil, device_info: {}, fingerprint_hash: nil)
      @admin_user = admin_user
      @lat = lat
      @lng = lng
      @accuracy = accuracy
      @ip = ip
      @device_info = device_info || {}
      @fingerprint_hash = fingerprint_hash
    end

    def call
      return fail_with(:feature_disabled) unless FieldFeatureGate.field_checkin_enabled?
      return fail_with(:not_field_agent)  unless FieldFeatureGate.field_agent_allowed?(@admin_user, tenant: @admin_user&.tenant)
      return fail_with(:missing_coordinates) if @lat.blank? || @lng.blank?
      # Rejeita coordenadas fora de faixa / lat-lng trocados ANTES de tocar o
      # geofence (PostGIS não valida faixa geográfica no input).
      return fail_with(:invalid_coordinates) unless Geo::Coordinates.valid_point?(@lat, @lng)
      return fail_with(:invalid_accuracy) unless accuracy_acceptable?
      return fail_with(:already_active) if @admin_user.active_check_in.present?

      discovery = DiscoverStoreService.new(
        lat: @lat, lng: @lng, tenant: @admin_user.tenant
      ).call
      return fail_with(:no_store_in_range) if discovery.nil? || !discovery[:inside_radius]

      store = discovery[:store]
      operational_shift = store.current_operational_shift(Time.current)
      return fail_with(:no_active_shift) if operational_shift.blank?

      check_in = CheckIn.new(
        admin_user: @admin_user,
        store: store,
        checked_in_at: Time.current,
        status: :active,
        checkin_latitude: @lat,
        checkin_longitude: @lng,
        checkin_accuracy_meters: @accuracy&.to_i,
        checkin_ip: @ip,
        device_info: device_info_with_signals,
        fingerprint_hash: @fingerprint_hash
      )
      if check_in.has_attribute?(:turno)
        check_in.turno = operational_shift
      end
      if check_in.has_attribute?(:status_chegada)
        check_in.status_chegada = store.arrival_status_for_shift(operational_shift, check_in.checked_in_at)
      end

      if check_in.save
        CheckinAuditLog.log!(
          action: "created",
          check_in: check_in,
          ip: @ip,
          metadata: {
            store_id: store.id,
            distance_meters: discovery[:distance_meters],
            accuracy: @accuracy&.to_i,
            manual: @device_info["manual"] == true,
            is_mock_location: mock_location?
          }
        )
        run_anti_fraud!(check_in)
        DistributionRules::AutoUpdateAgentsFromCheckinJob.perform_later(check_in.id) if defined?(DistributionRules::AutoUpdateAgentsFromCheckinJob)
        { success: true, check_in: check_in, distance_meters: discovery[:distance_meters] }
      else
        fail_with(:save_failed, check_in.errors.full_messages.to_sentence)
      end
    rescue ActiveRecord::RecordNotUnique
      fail_with(:already_active)
    end

    private

    # Política de accuracy: obrigatória para check-in por GPS. Ausente/<=0 é
    # tratado como reprovado (fecha o bypass de OMITIR o param). Check-in manual
    # (device_info["manual"] == true) é exceção legítima — não tem accuracy de GPS.
    def accuracy_acceptable?
      return true if manual_check_in?

      value = Geo::Coordinates.parse(@accuracy)
      return false if value.nil? || value <= 0

      value <= MAX_ACCURACY_METERS
    end

    def manual_check_in?
      @device_info["manual"] == true
    end

    # Lê o sinal nativo de mock location do device_info, tolerando bool/string
    # e chaves alternativas. Retorna true apenas quando explicitamente positivo.
    def mock_location?
      return @mock_location if defined?(@mock_location)

      raw = MOCK_LOCATION_KEYS.map { |k| @device_info[k] }.compact.first
      @mock_location =
        case raw
        when true then true
        when String then %w[true 1 yes].include?(raw.strip.downcase)
        else false
        end
    end

    # Persiste os sinais de device no device_info do check-in (normaliza o mock
    # sob a chave canônica is_mock_location, que o Analyzer de pings espera).
    def device_info_with_signals
      @device_info.merge(
        "is_mock_location" => mock_location?,
        "checkin_accuracy_meters" => @accuracy&.to_i
      )
    end

    # Verificação antifraude no INSTANTE do check-in (sem hard-block). Hoje
    # aplica a regra 1 do AntiFraud::CheckIns::Analyzer (mock_location nativo)
    # diretamente sobre os sinais do device, marcando suspeito + auditando.
    # As demais regras do Analyzer (velocidade, streak de accuracy, fingerprint
    # duplicado, ip_geo_mismatch) dependem de LocationPing e só rodam nos pings.
    #
    # ALTERNATIVA (produto): transformar em hard-block reprovando o check-in
    # quando mock_location? — não feito aqui para não reprovar corretor legítimo.
    def run_anti_fraud!(check_in)
      return unless mock_location?
      return unless check_in.respond_to?(:flag_suspicious!)

      check_in.flag_suspicious!(reasons: ["mock_location"])
      CheckinAuditLog.log!(
        action: "flagged_suspicious",
        check_in: check_in,
        ip: @ip,
        metadata: { reasons: ["mock_location"], source: "checkin_create" }
      )
    rescue StandardError => e
      # Antifraude é best-effort no create: nunca deve derrubar um check-in válido.
      Rails.logger.warn("[CheckIns::CreateService] anti_fraud skipped: #{e.class}: #{e.message}")
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
