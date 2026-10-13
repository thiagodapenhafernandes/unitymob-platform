# frozen_string_literal: true

module Ai
  # Registro de provedores de IA da Unitymob (OpenAI, Meta Muse e futuros).
  #
  # Seleção global por conta via setting `ai_provider` ("openai" por padrão),
  # feita em /admin/ai_integration. Todo o consumo (conteúdo, SEO, BI,
  # inteligência de interesses, busca/voice) resolve o provedor ativo aqui,
  # então trocar de provedor não exige mudar os chamadores.
  #
  # Para adicionar um provedor: criar cliente + catálogo com a mesma interface
  # de OpenAi::Client / OpenAi::ModelCatalog e registrar uma entrada em .all.
  class Provider
    SETTING = "ai_provider"
    DEFAULT_KEY = "openai"

    AUTOMATIC_VALUE = "__automatic__"
    CUSTOM_VALUE = "__custom__"

    MUSE_API_KEY_SETTING = "meta_api_key"
    MUSE_MODEL_SETTING = "meta_model"
    MUSE_VOICE_API_KEY_SETTING = "meta_property_search_api_key"
    MUSE_VOICE_MODEL_SETTING = "meta_property_search_model"
    MUSE_VOICE_TRANSCRIPTION_MODEL_SETTING = "meta_property_search_transcription_model"

    attr_reader :key, :label, :client_class, :catalog_class,
                :api_key_setting, :model_setting,
                :voice_api_key_setting, :voice_model_setting, :voice_transcription_model_setting,
                :default_model, :default_transcription_model, :token_placeholder

    def initialize(key:, label:, client_class:, catalog_class:,
                   api_key_setting:, model_setting:,
                   voice_api_key_setting:, voice_model_setting:, voice_transcription_model_setting:,
                   default_model:, default_transcription_model:, token_placeholder:)
      @key = key
      @label = label
      @client_class = client_class
      @catalog_class = catalog_class
      @api_key_setting = api_key_setting
      @model_setting = model_setting
      @voice_api_key_setting = voice_api_key_setting
      @voice_model_setting = voice_model_setting
      @voice_transcription_model_setting = voice_transcription_model_setting
      @default_model = default_model
      @default_transcription_model = default_transcription_model
      @token_placeholder = token_placeholder
    end

    class << self
      def all
        @all ||= {
          "openai" => new(
            key: "openai",
            label: "OpenAI",
            client_class: OpenAi::Client,
            catalog_class: OpenAi::ModelCatalog,
            api_key_setting: Ai::PropertyContentService::API_KEY_SETTING,
            model_setting: Ai::PropertyContentService::MODEL_SETTING,
            voice_api_key_setting: Ai::PropertySearch::Configuration::API_KEY_SETTING,
            voice_model_setting: Ai::PropertySearch::Configuration::MODEL_SETTING,
            voice_transcription_model_setting: Ai::PropertySearch::Configuration::TRANSCRIPTION_MODEL_SETTING,
            default_model: Ai::PropertyContentService::DEFAULT_MODEL,
            default_transcription_model: Ai::PropertySearch::Configuration::DEFAULT_TRANSCRIPTION_MODEL,
            token_placeholder: "Cole o token da OpenAI"
          ),
          "muse" => new(
            key: "muse",
            label: "Meta Muse",
            client_class: MetaAi::Client,
            catalog_class: MetaAi::ModelCatalog,
            api_key_setting: MUSE_API_KEY_SETTING,
            model_setting: MUSE_MODEL_SETTING,
            voice_api_key_setting: MUSE_VOICE_API_KEY_SETTING,
            voice_model_setting: MUSE_VOICE_MODEL_SETTING,
            voice_transcription_model_setting: MUSE_VOICE_TRANSCRIPTION_MODEL_SETTING,
            default_model: MetaAi::ModelCatalog::DEFAULT_RESPONSE_MODEL,
            default_transcription_model: MetaAi::ModelCatalog::DEFAULT_TRANSCRIPTION_MODEL,
            token_placeholder: "Cole o token da Meta (MODEL_API_KEY)"
          )
        }
      end

      def find(key)
        all.fetch(key.to_s.strip, all[DEFAULT_KEY])
      end

      def active_key(tenant: Current.tenant)
        key = Setting.tenant_get(SETTING, DEFAULT_KEY, tenant: tenant).to_s.strip
        all.key?(key) ? key : DEFAULT_KEY
      end

      def active(tenant: Current.tenant)
        find(active_key(tenant: tenant))
      end

      def build_client(tenant:, api_key: nil)
        provider = active(tenant: tenant)
        provider.build_client(api_key: api_key.presence || provider.api_key(tenant: tenant))
      end

      def automatic?(value)
        value.to_s.strip == AUTOMATIC_VALUE
      end

      def custom?(value)
        value.to_s.strip == CUSTOM_VALUE
      end
    end

    def api_key(tenant: Current.tenant)
      Setting.tenant_get(api_key_setting, nil, tenant: tenant).to_s
    end

    def connected?(tenant: Current.tenant)
      api_key(tenant: tenant).present?
    end

    def model(tenant: Current.tenant)
      Setting.tenant_get(model_setting, default_model, tenant: tenant).to_s.strip.presence || default_model
    end

    def resolved_model(tenant: Current.tenant)
      catalog_class.resolve_response_model(model(tenant: tenant))
    end

    def fallback_response_model(configured_model = nil)
      catalog_class.fallback_response_model(configured_model)
    end

    def voice_api_key(tenant: Current.tenant)
      dedicated_voice_api_key(tenant: tenant).presence || api_key(tenant: tenant)
    end

    def dedicated_voice_api_key(tenant: Current.tenant)
      Setting.tenant_get(voice_api_key_setting, nil, tenant: tenant).to_s.strip
    end

    def dedicated_voice_api_key_configured?(tenant: Current.tenant)
      dedicated_voice_api_key(tenant: tenant).present?
    end

    def voice_connected?(tenant: Current.tenant)
      voice_api_key(tenant: tenant).present?
    end

    def voice_model(tenant: Current.tenant)
      Setting.tenant_get(voice_model_setting, default_model, tenant: tenant).to_s.strip.presence || default_model
    end

    def resolved_voice_model(tenant: Current.tenant)
      catalog_class.resolve_response_model(voice_model(tenant: tenant))
    end

    def voice_transcription_model(tenant: Current.tenant)
      Setting.tenant_get(voice_transcription_model_setting, default_transcription_model, tenant: tenant).to_s.strip.presence || default_transcription_model
    end

    def resolved_voice_transcription_model(tenant: Current.tenant)
      catalog_class.resolve_transcription_model(voice_transcription_model(tenant: tenant))
    end

    def fallback_transcription_model(configured_model = nil)
      catalog_class.fallback_transcription_model(configured_model)
    end

    def response_model_options(api_key: nil, selected: nil)
      catalog_class.response_model_options(api_key: api_key, selected: selected)
    end

    def transcription_model_options(api_key: nil, selected: nil)
      catalog_class.transcription_model_options(api_key: api_key, selected: selected)
    end

    def known_response_model?(model)
      catalog_class.known_response_model?(model)
    end

    def known_transcription_model?(model)
      catalog_class.known_transcription_model?(model)
    end

    def build_client(api_key:)
      client_class.new(api_key: api_key)
    end
  end
end
