class MetaSyncJob < ApplicationJob
  queue_as :default

  def perform(integration_id)
    integration = UserMetaIntegration.find(integration_id)
    
    # Marcamos como 5% para indicar que o Job realmente começou
    integration.update!(sync_status: 'processing', sync_progress: 5, sync_message: "Iniciando conexão com a Meta...")
    broadcast_status(integration)

    service = Facebook::MetaService.new(integration.access_token)
    
    # 1. Sync Pages
    integration.update!(sync_message: "Buscando suas páginas no Facebook...")
    broadcast_status(integration)
    
    pages_data = service.get_user_pages
    total_pages = pages_data.size
    
    integration.update!(sync_progress: 20, sync_message: "Encontradas #{total_pages} páginas. Sincronizando...")
    broadcast_status(integration)

    synced_pages = []
    pages_data.each_with_index do |page_data, index|
      integration.update!(sync_message: "Sincronizando página: #{page_data['name']} (#{index + 1}/#{total_pages})")
      broadcast_status(integration)

      page = integration.meta_facebook_pages.find_or_initialize_by(page_id: page_data["id"])
      page.update!(
        name: page_data["name"],
        access_token: page_data["access_token"],
        category: page_data["category"],
        active: true
      )
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

          # Auto-add to Distribution Rules if enabled
          if is_new # Only for new forms effectively found
            DistributionRule.where(auto_add_forms: true).find_each do |rule|
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
        
        # Subscribe for webhooks
        page_service.subscribe_page_to_app(page.page_id, page.access_token)
      rescue => e
        Rails.logger.error "MetaSyncJob Error for page #{page.id}: #{e.message}"
      end
      
      # Progress for forms (50% to 95%)
      progress = 50 + (((index + 1).to_f / synced_pages.size) * 45).to_i
      integration.update!(sync_progress: progress)
      broadcast_status(integration)
      
      sleep(1.0) # Cadência maior entre páginas
    end

    integration.update!(sync_status: 'completed', sync_progress: 100, sync_message: "Sincronização finalizada!", last_synced_at: Time.current)
    broadcast_status(integration)
    
    # Reset status after 5 seconds
    ResetSyncStatusJob.set(wait: 5.seconds).perform_later(integration.id)
  rescue => e
    integration.update!(sync_status: 'failed', sync_progress: 0)
    broadcast_status(integration)
    Rails.logger.error "MetaSyncJob Fatal Error: #{e.message}"
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
end
