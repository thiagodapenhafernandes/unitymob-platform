module Habitations
  class BulkPublication
    CHANNELS = {
      "site"             => { flag: :exibir_no_site_flag, options: [] },
      "lais_ai"          => { flag: :publicar_lais_ai, options: [] },
      "chaves_na_mao"    => { flag: :publicar_chaves_na_mao, options: [:destaque_chaves_na_mao, :periodo_locacao_chaves_na_mao] },
      "casa_mineira"     => { flag: :publicar_casa_mineira, options: [:modelo_casa_mineira] },
      "imovelweb"        => { flag: :publicar_imovelweb, options: [:tipo_publicacao_imovelweb, :mostrar_mapa_imovelweb] },
      "imovelweb_2"      => { flag: :publicar_imovelweb_2, options: [:tipo_publicacao_imovelweb_2, :mostrar_mapa_imovelweb_2] },
      "viva_real_vrsync" => { flag: :publicar_viva_real_vrsync, options: [:tipo_publicacao_viva_real, :divulgar_endereco_viva_real] }
    }.freeze

    def initialize(tenant:, actor:, request:)
      raise ArgumentError, "ator fora da conta" unless tenant&.persisted? && actor&.tenant_id == tenant.id

      @tenant, @actor, @request = tenant, actor, request
    end

    def call(ids:, action_type:, channels:, channel_options:)
      action_type = action_type.to_s
      channels = Array(channels).map(&:to_s) & CHANNELS.keys

      if ids.empty?
        return { error: "Nenhum imóvel selecionado." }
      end
      unless %w[publicar despublicar].include?(action_type)
        return { error: "Ação inválida." }
      end
      if channels.empty?
        return { error: "Selecione ao menos um canal." }
      end

      updates = {}
      flag_value = (action_type == "publicar")
      site_flag_touched = false
      portals_touched = []

      channels.each do |channel_key|
        config = CHANNELS[channel_key]
        updates[config[:flag]] = flag_value
        site_flag_touched = true if config[:flag] == :exibir_no_site_flag
        portals_touched << channel_key unless channel_key == "site"

        if flag_value
          config[:options].each do |option_key|
            value = channel_options.dig(channel_key, option_key).presence
            updates[option_key] = value if value
          end
        end
      end

      target_ids = ids
      if flag_value
        target_ids = @tenant.habitations.where(id: ids).commercially_publishable.reorder(nil).pluck(:id)
        if target_ids.empty?
          return { error: "Nenhum imóvel selecionado pode ser publicado com o status comercial atual." }
        end
      end

      # Bump updated_at so feed ETags e cache_keys das habitations invalidem automaticamente
      updates[:updated_at] = Time.current
      bulk_audit_changesets = bulk_habitation_audit_changesets(target_ids, updates)

      updated_count = 0
      Habitation.transaction do
        updated_count = @tenant.habitations.where(id: target_ids).update_all(updates)
        record_bulk_habitation_updates(bulk_audit_changesets, action_type: action_type, channels: channels)
      end

      # Invalida caches individuais (replica o after_save :clear_cache manualmente, pois update_all pula callbacks)
      target_ids.each do |habitation_id|
        Rails.cache.delete("habitation_#{habitation_id}")
        Rails.cache.delete([Habitation.name, habitation_id])
      end

      # Materialized view de destaques depende de exibir_no_site_flag
      if site_flag_touched
        PublicSite::PageVersion.bump(@tenant.id)
        RefreshFeaturedPropertiesJob.perform_later if defined?(RefreshFeaturedPropertiesJob)
      end

      # Bump last_feed_at nas integrations afetadas pra sinalizar no admin que houve mudança
      if portals_touched.any?
        portal_keys = Habitation::PORTAL_PUBLICATION_FIELDS.select { |_, col| updates.key?(col) }.keys
        @tenant.portal_integrations.where(portal: portal_keys).update_all(updated_at: Time.current) if portal_keys.any?
      end

      {
        updated: updated_count,
        skipped_inactive_status: ids.size - target_ids.size,
        action_type: action_type,
        channels: channels
      }
    end

    private

    def bulk_habitation_audit_changesets(ids, updates)
      audit_fields = updates.keys.map(&:to_s) & Habitations::AuditChangeRecorder.audited_habitation_fields
      audit_fields -= %w[updated_at]
      return {} if audit_fields.blank?

      @tenant.habitations.where(id: ids).pluck(:id, *audit_fields).each_with_object({}) do |row, result|
        habitation_id = row.first
        changeset = {}

        audit_fields.each_with_index do |field, index|
          before_value = row[index + 1]
          after_value = updates.key?(field.to_sym) ? updates[field.to_sym] : updates[field]
          changeset[field] = { before: before_value, after: after_value }
        end

        result[habitation_id] = changeset
      end
    end

    def record_bulk_habitation_updates(changesets_by_id, action_type:, channels:)
      return if changesets_by_id.blank?

      @tenant.habitations.where(id: changesets_by_id.keys).find_each do |habitation|
        Habitations::AuditChangeRecorder.new(
          habitation,
          actor: @actor,
          request: @request,
          source: habitation.broker_intake? ? "captacao" : "admin"
        ).record_bulk_update!(
          changesets_by_id[habitation.id],
          metadata: {
            action_type: action_type,
            channels: channels
          }
        )
      end
    end

  end
end
