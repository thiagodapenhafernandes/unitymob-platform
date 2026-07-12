class Setting < ApplicationRecord
  # Key-value com escopo por CONTA e fallback global:
  # - leitura: linha do tenant vence; sem ela, vale a global; sem ambas, default.
  # - escrita: com tenant no contexto grava escopado; sem tenant (console,
  #   plataforma), grava global.
  # Linhas antigas seguem globais — cada conta "sombreia" ao salvar a própria.
  # Pré-migration (sem coluna tenant_id) mantém o comportamento antigo.
  belongs_to :tenant, optional: true

  # Chaves de PLATAFORMA: sempre globais, mesmo com tenant no contexto.
  GLOBAL_KEYS = %w[facebook_webhook_verify_token].freeze
  GLOBAL_KEY_PREFIXES = [].freeze

  validates :key, presence: true
  validates :key, uniqueness: { scope: :tenant_id }

  def self.tenant_scoping_available?
    column_names.include?("tenant_id")
  end

  def self.scoped_tenant_for(key, tenant)
    return nil unless tenant_scoping_available?
    return nil if GLOBAL_KEYS.include?(key.to_s)
    return nil if GLOBAL_KEY_PREFIXES.any? { |prefix| key.to_s.start_with?(prefix) }

    tenant
  end

  def self.get(key, default = nil, tenant: Current.tenant)
    scope_tenant = scoped_tenant_for(key, tenant)
    cache_key = [key.to_s, scope_tenant&.id]
    cache = request_cache
    return cache[cache_key] if cache.key?(cache_key)

    if scope_tenant
      scoped = find_by(tenant_id: scope_tenant.id, key: key)&.value
      return cache[cache_key] = scoped if scoped.present?
    end

    global = tenant_scoping_available? ? find_by(tenant_id: nil, key: key)&.value : find_by(key: key)&.value
    cache[cache_key] = global.presence || default
  end

  def self.set(key, value, description = nil, tenant: Current.tenant)
    scope_tenant = scoped_tenant_for(key, tenant)

    setting =
      if tenant_scoping_available?
        find_or_initialize_by(key: key, tenant_id: scope_tenant&.id)
      else
        find_or_initialize_by(key: key)
      end
    setting.value = value
    setting.description = description if description
    saved = setting.save
    clear_request_cache_for(key, scope_tenant) if saved
    saved
  end

  def self.request_cache
    begin
      return Current.setting_values_cache ||= {}
    rescue NoMethodError
      # Development hot reload can keep an older Current instance without this attribute.
    end
    Thread.current[:setting_values_cache] ||= {}
  end

  def self.clear_request_cache_for(key, scope_tenant)
    cache = request_cache
    cache.delete_if { |(cached_key, tenant_id), _| cached_key == key.to_s && tenant_id == scope_tenant&.id }
  end
end
