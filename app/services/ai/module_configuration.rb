module Ai
  # Vínculos por conta; campos vazios herdam as configurações existentes do provedor.
  class ModuleConfiguration
    SETTING = "ai_module_bindings".freeze
    MODULES = {
      "property_content" => { label: "Conteúdo de imóveis", tab: "Conteúdo", kind: :content },
      "seo" => { label: "SEO", tab: "Conteúdo", kind: :content },
      "property_search_text" => { label: "Busca por texto", tab: "Busca e voz", kind: :interpretation },
      "property_search_voice" => { label: "Busca por voz · interpretação", tab: "Busca e voz", kind: :interpretation },
      "property_search_transcription" => { label: "Busca por voz · transcrição", tab: "Busca e voz", kind: :transcription },
      "interest_summary" => { label: "Resumo de interesse do lead", tab: "Leads", kind: :content },
      "dashboard_diagnosis" => { label: "Diagnóstico do BI", tab: "Dados", kind: :content }
    }.freeze

    attr_reader :key, :tenant

    def initialize(key, tenant: Current.tenant)
      @key = key.to_s
      MODULES.fetch(@key)
      @tenant = tenant
    end

    def self.bindings(tenant:)
      JSON.parse(Setting.tenant_get(SETTING, "{}", tenant: tenant)).to_h
    rescue JSON::ParserError, TypeError
      {}
    end

    def self.save!(attributes, tenant:)
      raise ArgumentError, "Conta não informada." unless tenant

      updated = bindings(tenant: tenant).merge(attributes.to_h.stringify_keys)
      updated.each do |key, fields|
        raise ArgumentError, "Módulo de IA inválido." unless MODULES.key?(key)
        provider_key = fields.fetch("provider", "").to_s.strip
        model = fields.fetch("model", "").to_s.strip
        unless provider_key.blank? || Provider.all.key?(provider_key)
          raise ArgumentError, "Provedor de IA inválido."
        end
        if model.length > 200 || model.match?(/[\s\x00-\x1f]/) || Provider.custom?(model)
          raise ArgumentError, "Informe um nome de modelo válido (até 200 caracteres, sem espaços)."
        end
        updated[key] = { "provider" => provider_key, "model" => model }
      end
      record = Setting.find_or_initialize_by(key: SETTING, tenant: tenant)
      record.update!(value: updated.to_json, description: "Provedor e modelo de IA por módulo")
      Setting.clear_request_cache_for(SETTING, tenant)
    end

    def binding
      self.class.bindings(tenant: tenant).fetch(key, {}).to_h
    end

    def provider
      binding["provider"].presence ? Provider.find(binding["provider"]) : Provider.active(tenant: tenant)
    end

    def kind
      MODULES.fetch(key).fetch(:kind)
    end

    def api_key
      kind == :content ? provider.api_key(tenant: tenant) : provider.voice_api_key(tenant: tenant)
    end

    def connected?
      api_key.present?
    end

    def model
      binding["model"].presence || case kind
      when :interpretation then provider.voice_model(tenant: tenant)
      when :transcription then provider.voice_transcription_model(tenant: tenant)
      else provider.model(tenant: tenant)
      end
    end

    def resolved_model
      catalog = provider.catalog_class
      kind == :transcription ? catalog.resolve_transcription_model(model) : catalog.resolve_response_model(model)
    end

    def fallback_model
      kind == :transcription ? provider.fallback_transcription_model(resolved_model) : provider.fallback_response_model(resolved_model)
    end

    def build_client
      provider.build_client(api_key: api_key)
    end
  end
end
