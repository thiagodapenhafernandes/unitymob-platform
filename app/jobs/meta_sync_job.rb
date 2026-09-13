class MetaSyncJob < ApplicationJob
  queue_as :sync

  def perform(integration_id)
    integration = UserMetaIntegration.find_by(id: integration_id)
    return unless integration
    pending = []
    
    # Marcamos como 5% para indicar que o Job realmente começou
    integration.update!(sync_status: 'processing', sync_progress: 5, sync_message: "Iniciando conexão com a Meta...")
    broadcast_status(integration)

    service = Facebook::MetaService.new(integration.access_token)
    
    # 1. Sync Pages
    integration.update!(sync_message: "Buscando suas páginas no Facebook...")
    broadcast_status(integration)
    
    pages_data = service.get_user_pages
    # Preserve history, but stop synchronizing pages no longer authorized by Meta.
    integration.meta_facebook_pages.where.not(page_id: pages_data.map { |page| page["id"] }).update_all(active: false, instagram_enabled: false)
    missing_ids = integration.selected_page_ids - pages_data.map { |data| data["id"].to_s }
    pending << "A Meta não retornou páginas selecionadas (#{missing_ids.join(', ')}). Atualize a autorização mantendo os ativos das outras empresas selecionados. Sua seleção neste CRM foi preservada." if missing_ids.any?
    total_pages = pages_data.size
    
    integration.update!(sync_progress: 20, sync_message: "Encontradas #{total_pages} páginas. Sincronizando...")
    broadcast_status(integration)

    synced_pages = []
    pages_data.each_with_index do |page_data, index|
      integration.update!(sync_message: "Sincronizando páginas (#{index + 1}/#{total_pages})")
      broadcast_status(integration)

      page = integration.meta_facebook_pages.find_or_initialize_by(page_id: page_data["id"])
      selected = false
      integration.with_lock do
        selected = integration.selected_page_ids.include?(page_data["id"].to_s)
        page.update!(
          name: page_data["name"],
          access_token: page_data["access_token"],
          category: page_data["category"],
          active: selected && page.persisted? && page.active?
        )
      end
      next unless selected

      # Proposta de ativação: só persiste depois de confirmar o destino.
      page.active = true
      unless register_meta_gateway_route(page, integration)
        page.update!(active: false, instagram_enabled: false)
        pending << "Gateway da página #{page.name}: registro pendente. O recebimento foi desativado até confirmar o destino."
        next
      end
      integration.with_lock do
        page.update!(active: integration.selected_page_ids.include?(page.page_id))
      end
      next unless page.active?

      begin
        Instagram::Connection.discover(page)
        if page.instagram_id.present?
          Instagram::Connection.activate(page)
        else
          page.update!(instagram_enabled: false, instagram_sync_error: nil, instagram_checked_at: Time.current)
        end
      rescue StandardError => error
        reason = error.is_a?(Instagram::Connection::Error) ? error.message : UserMetaIntegration.sync_failure_reason(error)
        page.update!(instagram_enabled: false, instagram_sync_error: reason, instagram_checked_at: Time.current)
        pending << "Instagram da página #{page.name}: #{reason}"
        Rails.logger.warn("[Instagram] descoberta pendente page_id=#{page.id} error=#{error.class}")
      end
      synced_pages << page
      
      # Progress for pages (up to 50%)
      progress = 20 + (((index + 1).to_f / total_pages) * 30).to_i
      integration.update!(sync_progress: progress)
      broadcast_status(integration)
      
      sleep(0.5) # Cadência para não sobrecarregar
    end

    # 2. Sync Forms for each page
    total_synced_pages = synced_pages.size
    synced_pages.each_with_index do |page, index|
      next unless integration.reload.selected_page_ids.include?(page.page_id)
      begin
        integration.update!(sync_message: "Buscando formulários da página: #{page.name} (#{index + 1}/#{total_synced_pages})")
        broadcast_status(integration)

        page_service = Facebook::MetaService.new(page.access_token || integration.access_token)
        forms_data = page_service.get_page_lead_forms(page.page_id, page.access_token)
        
        integration.update!(sync_message: "Sincronizando #{forms_data.size} formulários de #{page.name}...")
        broadcast_status(integration)

        forms_data.each do |form_data|
          form = page.meta_lead_forms.find_or_initialize_by(form_id: form_data["id"])
          is_new = form.new_record?
          
          form.update!(
            name: form_data["name"],
            active: form_data["status"] == "ACTIVE",
            facebook_created_at: form_data["created_time"]
          )
          pending << "Gateway do formulário #{form.name}: registro pendente." unless register_meta_gateway_route(page, integration, form: form)

          # Auto-add to Distribution Rules if enabled — SÓ do tenant desta
          # integração (antes varria todos; com páginas duplicadas entre
          # contas, adicionaria forms em regra de tenant alheio).
          if is_new # Only for new forms effectively found
            DistributionRule.where(auto_add_forms: true, tenant_id: integration.owner_tenant_id).find_each do |rule|
              Current.set(tenant: rule.tenant) do
                # Check if the rule is watching this page
                if rule.meta_page_ids.include?(page.page_id)
                  current_forms = rule.meta_forms || []
                  unless current_forms.include?(form.form_id)
                    rule.update!(meta_forms: current_forms + [form.form_id])
                  end
                end
              end
            end
          end
        end
        
      rescue StandardError => e
        pending << "Formulários da página #{page.name}: #{UserMetaIntegration.sync_failure_reason(e)}"
        Rails.logger.error "MetaSyncJob forms page_id=#{page.id} error=#{e.class}"
      end

      # A consulta dos formulários não deve impedir a inscrição da página.
      begin
        Facebook::MetaService.new(page.access_token || integration.access_token).subscribe_page_to_app(page.page_id, page.access_token)
      rescue StandardError => e
        pending << "Webhook da página #{page.name}: #{UserMetaIntegration.sync_failure_reason(e)}"
        Rails.logger.error "MetaSyncJob subscription page_id=#{page.id} error=#{e.class}"
      end
      
      # Progress for forms (50% to 95%)
      progress = 50 + (((index + 1).to_f / synced_pages.size) * 45).to_i
      integration.update!(sync_progress: progress)
      broadcast_status(integration)
      
      sleep(1.0) # Cadência maior entre páginas
    end

    integration.update!(sync_status: pending.empty? ? 'completed' : 'partial', sync_progress: 100,
      sync_message: pending.empty? ? "Sincronização finalizada!" : pending.uniq.join(" "),
      last_sync_error: pending.empty? ? nil : pending.uniq.join(" "), last_synced_at: Time.current)
    broadcast_status(integration)
    
    Turbo::StreamsChannel.broadcast_replace_to("meta_sync_#{integration.id}", target: "meta_pages",
      partial: "admin/meta_integrations/pages", locals: { pages: integration.meta_facebook_pages.enabled.where(page_id: integration.selected_page_ids) })

    Turbo::StreamsChannel.broadcast_replace_to("meta_selection_#{integration.id}", target: "meta_page_selection",
      partial: "admin/meta_integrations/page_selection", locals: { integration: integration })

    # Reset status after 5 seconds
    ResetSyncStatusJob.set(wait: 5.seconds).perform_later(integration.id, integration.updated_at.iso8601(6)) if pending.empty?
  rescue => e
    reason = [*pending, integration&.sync_message, UserMetaIntegration.sync_failure_reason(e)].compact.join(" ")
    integration&.update!(sync_status: 'failed', sync_progress: 0, sync_message: reason, last_sync_error: reason)
    broadcast_status(integration) if integration
    Rails.logger.error "MetaSyncJob Fatal Error: #{e.class}"
    raise e
  end

  private

  def broadcast_status(integration)
    Turbo::StreamsChannel.broadcast_replace_to(
      "meta_sync_#{integration.id}",
      target: "meta_sync_status",
      partial: "admin/meta_integrations/sync_status",
      locals: { integration: integration }
    )
  end

  def register_meta_gateway_route(page, integration, form: nil)
    tenant = Tenant.find_by(id: integration.owner_tenant_id)
    return false unless tenant

    result = Meta::WebhookGatewayClient.new(page: page, tenant: tenant, form: form).register_route
    return true if result.ok? || (result.skipped? && !Meta::WebhookConfiguration.gateway?)

    Rails.logger.warn(
      "[MetaSyncJob] Nao foi possivel registrar rota Meta no gateway " \
      "page_id=#{page.page_id} form_id=#{form&.form_id} tenant_id=#{tenant.id} " \
      "status=#{result.status}"
    )
    false
  rescue => e
    Rails.logger.warn(
      "[MetaSyncJob] Erro ao registrar rota Meta no gateway " \
      "page_id=#{page.page_id} form_id=#{form&.form_id} error=#{e.class}"
    )
    false
  end
end
