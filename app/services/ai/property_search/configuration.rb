module Ai
  module PropertySearch
    module Configuration
      API_KEY_SETTING = "openai_property_search_api_key".freeze
      MODEL_SETTING = "openai_property_search_model".freeze
      TRANSCRIPTION_MODEL_SETTING = "openai_property_search_transcription_model".freeze

      DEFAULT_MODEL = Ai::PropertyContentService::DEFAULT_MODEL
      DEFAULT_TRANSCRIPTION_MODEL = "gpt-4o-mini-transcribe".freeze

      module_function

      def api_key(tenant: Current.tenant)
        dedicated_api_key(tenant:).presence ||
          Setting.tenant_get(Ai::PropertyContentService::API_KEY_SETTING, nil, tenant:).to_s.strip
      end

      def dedicated_api_key(tenant: Current.tenant)
        Setting.tenant_get(API_KEY_SETTING, nil, tenant:).to_s.strip
      end

      def dedicated_api_key_configured?(tenant: Current.tenant)
        dedicated_api_key(tenant:).present?
      end

      def connected?(tenant: Current.tenant)
        api_key(tenant:).present?
      end

      def model(tenant: Current.tenant)
        Setting.tenant_get(MODEL_SETTING, DEFAULT_MODEL, tenant:).to_s.strip.presence || DEFAULT_MODEL
      end

      def transcription_model(tenant: Current.tenant)
        Setting.tenant_get(TRANSCRIPTION_MODEL_SETTING, DEFAULT_TRANSCRIPTION_MODEL, tenant:).to_s.strip.presence || DEFAULT_TRANSCRIPTION_MODEL
      end
    end
  end
end
