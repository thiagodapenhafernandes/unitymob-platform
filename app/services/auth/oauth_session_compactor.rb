module Auth
  class OauthSessionCompactor
    DISCARDABLE_SESSION_KEYS = %w[
      admin_context_items
      admin_context_skip_once_item_keys
    ].freeze

    DISCARDABLE_SESSION_KEY_PREFIXES = %w[
      admin_habitations_last_filter:
    ].freeze

    class << self
      def before_request_phase(env)
        new(env).before_request_phase
      end

      def after_request_phase(env)
        new(env).after_request_phase
      end
    end

    def initialize(env)
      @env = env
      @session = env["rack.session"]
    end

    def before_request_phase
      return unless facebook_request?
      return unless session.respond_to?(:keys)

      delete_discardable_session_data!
      delete_omniauth_session_payload!
    end

    def after_request_phase
      return unless facebook_request?
      return unless session.respond_to?(:keys)

      delete_omniauth_session_payload!
    end

    private

    attr_reader :env, :session

    def facebook_request?
      strategy_name = env["omniauth.strategy"]&.name.to_s
      return true if strategy_name == "facebook"

      path = env["PATH_INFO"].to_s
      path == "/auth/facebook" || path == "/auth/facebook/callback"
    end

    def delete_discardable_session_data!
      DISCARDABLE_SESSION_KEYS.each do |key|
        session.delete(key)
        session.delete(key.to_sym)
      end

      session.keys.map(&:to_s).each do |key|
        next unless DISCARDABLE_SESSION_KEY_PREFIXES.any? { |prefix| key.start_with?(prefix) }

        session.delete(key)
        session.delete(key.to_sym)
      end
    end

    def delete_omniauth_session_payload!
      session.delete("omniauth.params")
      session.delete(:"omniauth.params")
      session.delete("omniauth.origin")
      session.delete(:"omniauth.origin")
    end
  end
end
