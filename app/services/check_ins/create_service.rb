# frozen_string_literal: true

module CheckIns
  # Cria um CheckIn após validar:
  # - feature flag ligada
  # - corretor habilitado (field_agent_enabled)
  # - sem check-in ativo
  # - accuracy aceitável (<= 50m)
  # - loja resolvida dentro do raio
  # - turno ativo naquela loja agora
  #
  # Retorna:
  #   { success: true, check_in: CheckIn } em caso de sucesso
  #   { success: false, error: Symbol, message: String } em caso de erro
  class CreateService
    MAX_ACCURACY_METERS = 50

    ERRORS = {
      feature_disabled:      "Feature de check-in não está habilitada.",
      not_field_agent:       "Você não está habilitado como corretor de campo.",
      already_active:        "Você já tem um check-in ativo. Faça check-out antes.",
      invalid_accuracy:      "Sinal de GPS muito fraco. Tente novamente em local aberto.",
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
      return fail_with(:not_field_agent)  unless @admin_user&.field_agent_enabled?
      return fail_with(:missing_coordinates) if @lat.blank? || @lng.blank?
      return fail_with(:invalid_accuracy) if @accuracy.present? && @accuracy.to_f > MAX_ACCURACY_METERS
      return fail_with(:already_active) if @admin_user.active_check_in.present?

      discovery = DiscoverStoreService.new(
        lat: @lat, lng: @lng, prefer_store: @admin_user.default_store, tenant: @admin_user.tenant
      ).call
      return fail_with(:no_store_in_range) if discovery.nil? || !discovery[:inside_radius]

      store = discovery[:store]
      shift = active_shift_for(store)
      return fail_with(:no_active_shift) if shift.nil?

      check_in = CheckIn.new(
        admin_user: @admin_user,
        store: store,
        store_shift: shift,
        checked_in_at: Time.current,
        status: :active,
        checkin_latitude: @lat,
        checkin_longitude: @lng,
        checkin_accuracy_meters: @accuracy&.to_i,
        checkin_ip: @ip,
        device_info: @device_info,
        fingerprint_hash: @fingerprint_hash
      )

      if check_in.save
        CheckinAuditLog.log!(
          action: "created",
          check_in: check_in,
          ip: @ip,
          metadata: {
            store_id: store.id,
            distance_meters: discovery[:distance_meters],
            accuracy: @accuracy&.to_i,
            manual: @device_info["manual"] == true
          }
        )
        { success: true, check_in: check_in, distance_meters: discovery[:distance_meters] }
      else
        fail_with(:save_failed, check_in.errors.full_messages.to_sentence)
      end
    rescue ActiveRecord::RecordNotUnique
      fail_with(:already_active)
    end

    private

    def active_shift_for(store)
      now = Time.current.in_time_zone(store.timezone_obj)
      @admin_user.store_shifts
                 .where(store: store, active: true, day_of_week: now.wday)
                 .to_a
                 .find { |s| s.active_at?(Time.current) }
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
