module Ai
  module PropertySearch
    module Configuration
      API_KEY_SETTING = "openai_property_search_api_key".freeze
      MODEL_SETTING = "openai_property_search_model".freeze
      TRANSCRIPTION_MODEL_SETTING = "openai_property_search_transcription_model".freeze

      DEFAULT_MODEL = Ai::PropertyContentService::DEFAULT_MODEL
      DEFAULT_TRANSCRIPTION_MODEL = "gpt-4o-mini-transcribe".freeze

      module_function

      def configuration(tenant: Current.tenant, voice: false)
        Ai::ModuleConfiguration.new(voice ? :property_search_voice : :property_search_text, tenant: tenant)
      end

      def api_key(tenant: Current.tenant)
        configuration(tenant: tenant).api_key
      end

      def dedicated_api_key(tenant: Current.tenant)
        configuration(tenant: tenant).provider.dedicated_voice_api_key(tenant: tenant)
      end

      def dedicated_api_key_configured?(tenant: Current.tenant)
        dedicated_api_key(tenant: tenant).present?
      end

      def connected?(tenant: Current.tenant)
        configuration(tenant: tenant).connected?
      end

      def voice_connected?(tenant: Current.tenant)
        configuration(tenant: tenant, voice: true).connected? &&
          Ai::ModuleConfiguration.new(:property_search_transcription, tenant: tenant).connected?
      end

      def model(tenant: Current.tenant)
        configuration(tenant: tenant).model
      end

      def resolved_model(tenant: Current.tenant)
        configuration(tenant: tenant).resolved_model
      end

      def transcription_model(tenant: Current.tenant)
        Ai::ModuleConfiguration.new(:property_search_transcription, tenant: tenant).model
      end

      def resolved_transcription_model(tenant: Current.tenant)
        Ai::ModuleConfiguration.new(:property_search_transcription, tenant: tenant).resolved_model
      end
    end
  end
end
