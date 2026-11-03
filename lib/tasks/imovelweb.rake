namespace :imovelweb do
  desc "Prepare a DISABLED connection for TENANT_ID; ENVIRONMENT defaults to sandbox. No remote changes."
  task prepare: :environment do
    tenant = Tenant.find(ENV.fetch("TENANT_ID"))
    environment = ENV.fetch("ENVIRONMENT", "sandbox")
    # UUID remains globally unique across independent customer installations.
    connection = ImovelwebConnection.create!(tenant: tenant, environment: environment, client_code: SecureRandom.uuid)
    puts "connection_id=#{connection.id} client_code=#{connection.client_code} environment=#{connection.environment} enabled=false"
  end

  desc "Map an explicitly associated listing. TENANT_ID CONNECTION_ID HABITATION_ID REFERENCE EXTERNAL_ID"
  task map_listing: :environment do
    connection = ImovelwebConnection.find_by!(id: ENV.fetch("CONNECTION_ID"), tenant_id: ENV.fetch("TENANT_ID"))
    property = Habitation.find_by!(id: ENV.fetch("HABITATION_ID"), tenant_id: connection.tenant_id)
    listing = connection.imovelweb_listings.find_or_initialize_by(reference: ENV.fetch("REFERENCE"))
    listing.update!(habitation: property, external_id: ENV.fetch("EXTERNAL_ID"))
    puts "listing_id=#{listing.id} mapped=true"
  end

  desc "Synchronize ONLY this connection's current route (does not enable reception). TENANT_ID CONNECTION_ID"
  task sync_route: :environment do
    connection = ImovelwebConnection.find_by!(id: ENV.fetch("CONNECTION_ID"), tenant_id: ENV.fetch("TENANT_ID"))
    Imovelweb::GatewayClient.sync!(connection)
    puts "route_synced=true active=#{connection.receiving?}"
  end

  desc "Inspect receipt status without contact data. TENANT_ID CONNECTION_ID"
  task status: :environment do
    connection = ImovelwebConnection.find_by!(id: ENV.fetch("CONNECTION_ID"), tenant_id: ENV.fetch("TENANT_ID"))
    puts "environment=#{connection.environment} enabled=#{connection.enabled?} authorized=#{connection.authorized_at.present?} receiving=#{connection.receiving?}"
    puts "last_lead_received_at=#{connection.last_lead_received_at&.iso8601}"
    connection.imovelweb_lead_receipts.group(:status, :reason).count.each { |(status, reason), count| puts "#{status} #{reason}: #{count}" }
  end

  desc "Retry ONE pending/quarantined receipt after correction. Dry-run unless APPLY=true. TENANT_ID CONNECTION_ID RECEIPT_ID"
  task retry_receipt: :environment do
    connection = ImovelwebConnection.find_by!(id: ENV.fetch("CONNECTION_ID"), tenant_id: ENV.fetch("TENANT_ID"))
    receipt = connection.imovelweb_lead_receipts.find(ENV.fetch("RECEIPT_ID"))
    abort "Connection not receiving" unless connection.receiving?
    abort "Receipt already processed" if receipt.status == "processed"
    puts "receipt_id=#{receipt.id} status=#{receipt.status} apply=#{ENV['APPLY'] == 'true'}"
    if ENV["APPLY"] == "true"
      receipt.with_lock do
        abort "Receipt already processed" if receipt.status == "processed"
        receipt.update!(status: "pending", reason: nil, processed_at: nil)
        ImovelwebLeadProcessingJob.perform_later(receipt.id)
      end
    end
  end
end
