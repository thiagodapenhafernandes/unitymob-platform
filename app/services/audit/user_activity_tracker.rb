module Audit
  class UserActivityTracker
    SESSION_TIMEOUT = 30.minutes
    MAX_VISIBLE_HABITATION_IDS = 250
    MAX_QUERY_TEXT_LENGTH = 500
    MAX_PATH_LENGTH = 255
    REDACTED_VALUE = "[redigido]".freeze
    IGNORED_FILTER_KEYS = %w[
      authenticity_token
      utf8
      commit
      controller
      action
      format
    ].freeze
    SENSITIVE_KEY_PATTERN = /(token|password|senha|secret|api_key|authorization|cookie|cpf|cnpj|email|telefone|phone|celular)/i

    def self.call(...)
      new(...).call
    end

    def initialize(tenant:, admin_user:, request:, event_name:, habitation: nil, query_text: nil,
                   filter_params: {}, result_count: nil, visible_habitation_ids: [], duration_seconds: nil,
                   metadata: {})
      @tenant = tenant
      @admin_user = admin_user
      @request = request
      @event_name = event_name.to_s
      @habitation = habitation
      @query_text = query_text
      @filter_params = filter_params
      @result_count = result_count
      @visible_habitation_ids = visible_habitation_ids
      @duration_seconds = duration_seconds
      @metadata = metadata
    end

    def call
      return unless @tenant && @admin_user && @request
      return unless OperationalUserEvent::EVENT_NAMES.include?(@event_name)

      occurred_at = Time.current
      activity_session = current_or_new_session(occurred_at)
      event = activity_session.events.create!(
        tenant: @tenant,
        admin_user: @admin_user,
        habitation: @habitation,
        name: @event_name,
        path: @request.fullpath.to_s.first(MAX_PATH_LENGTH),
        request_method: @request.request_method,
        occurred_at:,
        duration_seconds: normalized_duration,
        query_text: normalized_query_text,
        result_count: normalized_result_count,
        filter_params: sanitized_hash(@filter_params),
        visible_habitation_ids: normalized_visible_habitation_ids,
        metadata: sanitized_hash(@metadata)
      )
      activity_session.record_event!(occurred_at:)
      event
    rescue => e
      Rails.logger.warn("[UserActivityTracker] #{e.class}: #{e.message}")
      nil
    end

    private

    def current_or_new_session(now)
      existing = OperationalUserSession
        .where(id: @request.session[:operational_user_session_id], tenant: @tenant, admin_user: @admin_user)
        .first

      if existing && existing.last_seen_at >= SESSION_TIMEOUT.ago
        return existing
      end

      existing&.update_columns(ended_at: existing.last_seen_at, updated_at: Time.current) if existing&.ended_at.blank?

      device = AccessAudit::DeviceParser.call(@request.user_agent.to_s)
      OperationalUserSession.create!(
        tenant: @tenant,
        admin_user: @admin_user,
        started_at: now,
        last_seen_at: now,
        device_type: device[:device_type],
        browser: device[:browser],
        platform: device[:platform],
        ip_digest: digest(@request.remote_ip.to_s).first(32),
        user_agent_digest: digest(@request.user_agent.to_s).first(64),
        entry_path: @request.fullpath.to_s.first(MAX_PATH_LENGTH)
      ).tap do |activity_session|
        @request.session[:operational_user_session_id] = activity_session.id
      end
    end

    def normalized_query_text
      @query_text.to_s.squish.first(MAX_QUERY_TEXT_LENGTH).presence
    end

    def normalized_result_count
      return if @result_count.nil?

      Integer(@result_count, exception: false).to_i.clamp(0, 1_000_000)
    end

    def normalized_duration
      return if @duration_seconds.nil?

      Integer(@duration_seconds, exception: false).to_i.clamp(0, 86_400)
    end

    def normalized_visible_habitation_ids
      Array(@visible_habitation_ids)
        .filter_map { |id| Integer(id, exception: false) }
        .uniq
        .first(MAX_VISIBLE_HABITATION_IDS)
    end

    def sanitized_hash(value)
      normalized = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
      return {} unless normalized.is_a?(Hash)

      normalized.to_h.each_with_object({}) do |(key, raw_value), memo|
        string_key = key.to_s
        next if IGNORED_FILTER_KEYS.include?(string_key)
        next if raw_value.respond_to?(:blank?) ? raw_value.blank? : raw_value.nil?

        memo[string_key] = sanitize_value(string_key, raw_value)
      end
    end

    def sanitize_value(key, value)
      return REDACTED_VALUE if key.match?(SENSITIVE_KEY_PATTERN)

      case value
      when Hash
        sanitized_hash(value)
      when Array
        value.filter_map { |item| sanitize_scalar(key, item) }.first(50)
      else
        sanitize_scalar(key, value)
      end
    end

    def sanitize_scalar(key, value)
      return REDACTED_VALUE if key.match?(SENSITIVE_KEY_PATTERN)
      return if value.respond_to?(:blank?) && value.blank?

      value.is_a?(Numeric) || value == true || value == false ? value : value.to_s.squish.first(255)
    end

    def digest(value)
      Digest::SHA256.hexdigest(value)
    end
  end
end
