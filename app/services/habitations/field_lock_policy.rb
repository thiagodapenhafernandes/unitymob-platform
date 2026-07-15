# frozen_string_literal: true

module Habitations
  # Resolve, para um admin_user, QUAIS campos/ações do cadastro estão travados,
  # a partir da config do perfil (profile.permissions["imoveis"]["locked_fields"])
  # ou, na ausência dela, do DEFAULT atual (matriz do card #1 em BrokerEditPolicy).
  #
  # Fonte de itens: Habitations::CadastroFieldRegistry.
  #
  # FASE 2: o gatilho de "edita tudo" ainda é o atual (dono do tenant OU imoveis
  # escopo "all"), via #unrestricted?, para não mudar comportamento antes do seed.
  # A virada para "só o dono edita tudo" acontece na Fase 4 (seed) — trocar o
  # corpo de #unrestricted? para `tenant_owner_only?`.
  class FieldLockPolicy
    DEFAULT_EDITABLE_ACTION_KEYS = %w[
      acao:abrir_organizador_midia acao:organizar_fotos acao:enviar_fotos
      acao:alterar_visibilidade_fotos acao:gerenciar_ordem_fotos
      acao:configurar_ambiente_foto acao:remover_foto
    ].freeze
    def self.for(admin_user)
      new(admin_user)
    end

    def initialize(admin_user)
      @admin_user = admin_user
    end

    # Card #1 (Fase 4): SÓ o dono da conta edita tudo. Todo o resto é por perfil
    # (a config de full-access foi semeada com locked_fields: [] na migração).
    def unrestricted?
      tenant_owner?
    end

    def locked_keys
      @locked_keys ||= if unrestricted?
        Set.new
      else
        configured_locked_keys || self.class.default_locked_keys
      end
    end

    def field_locked?(key)
      locked_keys.include?(key.to_s)
    end

    def action_locked?(action_key)
      field_locked?(action_key)
    end

    # Params de topo (habitation[<param>]) liberados, incluindo os extra_params
    # (ex.: um item "Fotos" libera ordered_photo_ids, site_hidden_photo_ids...).
    def allowed_top_level_params
      (allowed_field_items + allowed_action_items).flat_map do |item|
        [CadastroFieldRegistry.top_level_param_for(item[:key]), *item[:extra_params]]
      end.compact.uniq
    end

    # Identificadores que o front (broker-field-policy) usa para reconhecer os
    # campos liberados — inclui paths aninhados (address_attributes.imediacoes)
    # e extra_params. Formato igual ao BrokerEditPolicy::ALLOWED_FIELDS.
    def allowed_frontend_fields
      (allowed_field_items + allowed_action_items).flat_map do |item|
        [item[:param_path] || item[:key], *item[:extra_params]]
      end.compact.reject { |key| key.start_with?("acao:") }.uniq
    end

    def allowed_action_keys
      CadastroFieldRegistry.all_items
        .select { |item| item[:kind] == :action && !field_locked?(item[:key]) }
        .map { |item| item[:key] }
    end

    # Sub-chaves liberadas dentro de address_attributes (ex.: imediacoes).
    def allowed_address_subkeys
      allowed_field_items.filter_map do |item|
        path = item[:param_path].to_s
        path.split(".").last if path.start_with?("address_attributes.")
      end.uniq
    end

    private

    attr_reader :admin_user

    def allowed_field_items
      CadastroFieldRegistry.field_items.reject { |item| field_locked?(item[:key]) }
    end

    def allowed_action_items
      CadastroFieldRegistry.all_items.select do |item|
        item[:kind] == :action && !field_locked?(item[:key])
      end
    end

    def tenant_owner?
      admin_user&.tenant_owner? || false
    end

    def owns_all_imoveis?
      permissions.dig("imoveis", "scope").to_s == "all"
    end

    def permissions
      admin_user&.profile&.permissions || {}
    end

    # nil quando o perfil ainda não foi configurado (cai no default).
    def configured_locked_keys
      raw = permissions.dig("imoveis", "locked_fields")
      return nil unless raw.is_a?(Array)

      Set.new(raw.map(&:to_s))
    end

    class << self
      # Conjunto travado EFETIVO de um perfil (para renderizar o modal): usa a
      # config salva (locked_fields) quando presente, senão o default do card #1.
      def effective_locked_keys_for(imoveis_permissions)
        raw = imoveis_permissions.is_a?(Hash) ? imoveis_permissions["locked_fields"] : nil
        return Set.new(raw.map(&:to_s)) if raw.is_a?(Array)

        default_locked_keys
      end

      # Default = comportamento atual do card #1: editável só o que está em
      # BrokerEditPolicy (allowlist + address_attributes.imediacoes); todo o
      # resto (incl. todas as ações) nasce travado.
      def default_locked_keys
        @default_locked_keys ||= begin
          editable = default_editable_keys
          Set.new(CadastroFieldRegistry.all_keys - editable.to_a)
        end
      end

      def default_editable_keys
        allowed = BrokerEditPolicy::ALLOWED_FIELDS.to_set
        fields = CadastroFieldRegistry.field_items.filter_map do |item|
          path = item[:param_path] || item[:key]
          item[:key] if allowed.include?(path) || allowed.include?(item[:key])
        end
        (fields + DEFAULT_EDITABLE_ACTION_KEYS).to_set
      end
    end
  end
end
