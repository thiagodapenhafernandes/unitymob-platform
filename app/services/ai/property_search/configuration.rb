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
        Ai::Provider.active(tenant: tenant).voice_api_key(tenant: tenant)
      end

      def dedicated_api_key(tenant: Current.tenant)
        Ai::Provider.active(tenant: tenant).dedicated_voice_api_key(tenant: tenant)
      end

      def dedicated_api_key_configured?(tenant: Current.tenant)
        Ai::Provider.active(tenant: tenant).dedicated_voice_api_key_configured?(tenant: tenant)
      end

      def connected?(tenant: Current.tenant)
        Ai::Provider.active(tenant: tenant).voice_connected?(tenant: tenant)
      end

      def model(tenant: Current.tenant)
        Ai::Provider.active(tenant: tenant).voice_model(tenant: tenant)
      end

      def resolved_model(tenant: Current.tenant)
        Ai::Provider.active(tenant: tenant).resolved_voice_model(tenant: tenant)
      end

      def transcription_model(tenant: Current.tenant)
        Ai::Provider.active(tenant: tenant).voice_transcription_model(tenant: tenant)
      end

      def resolved_transcription_model(tenant: Current.tenant)
        Ai::Provider.active(tenant: tenant).resolved_voice_transcription_model(tenant: tenant)
      end
    end
  end
end
