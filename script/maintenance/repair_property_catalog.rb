# Run with rails runner. Dry-run is the default; always name a tenant and property codes.
require "json"

tenant = Tenant.find(ENV.fetch("TENANT_ID"))
codes = ENV.fetch("CODES").split(",").map(&:strip).reject(&:blank?).uniq
operations = ENV.fetch("OPERATIONS").split(",").map(&:strip).uniq
allowed = %w[slugs maps dwv_photos owner_contacts]
raise ArgumentError, "Informe códigos e operações válidas: #{allowed.join(', ')}" if codes.empty? || operations.empty? || (operations - allowed).any?
execute = ENV["EXECUTE"] == "1"

Current.set(tenant: tenant) do
  codes.each do |code|
    habitation = tenant.habitations.find_by(codigo: code)
    unless habitation
      puts({ code: code, status: "not_found" }.to_json)
      next
    end

    operations.each do |operation|
      result = { code: code, operation: operation, execute: execute }
      case operation
      when "slugs"
        if habitation.slug.blank? || habitation.send(:slug_category_mismatch?)
          result[:before] = habitation.slug
          habitation.send(:set_slug)
          result[:after] = habitation.slug
          habitation.save! if execute
        else
          result[:status] = "already_valid"
        end
      when "maps"
        address = habitation.address
        if address && (address.latitude.blank? || address.longitude.blank?) && (habitation.latitude.blank? || habitation.longitude.blank?)
          setting = GoogleMapsIntegrationSetting.for(tenant)
          if setting.configured? && setting.provider == "google"
            HabitationGeocodeJob.perform_later(habitation.id, tenant_id: tenant.id) if execute
            result[:status] = execute ? "queued" : "would_queue"
          else
            result[:status] = "google_maps_not_configured"
          end
        else
          result[:status] = "coordinates_present_or_address_missing"
        end
      when "dwv_photos"
        if habitation.dwv_property? && PropertySetting.instance(tenant: tenant).watermark_configured?
          DwvPhotoWatermarkJob.perform_later(habitation.id, tenant_id: tenant.id) if execute
          result[:status] = execute ? "queued" : "would_queue"
        else
          result[:status] = "not_dwv_or_watermark_missing"
        end
      when "owner_contacts"
        service = SyncPropertyService.new(code)
        payload = service.send(:fetch_details, code)
        source = service.send(:extract_owner_data, payload&.dig("proprietarios"))
        habitation.with_lock do
          owner = habitation.proprietor
          owner.lock! if owner
          if owner && source["Codigo"].present? && source["Codigo"].to_s == owner.vista_code.to_s
            fields = { phone_primary: source["FonePrincipal"], mobile_phone: source["Celular"], business_phone: source["FoneComercial"], residential_phone: source["FoneResidencial"], email: source["EmailResidencial"].presence || source["Email"] }
            fields.select! { |field, value| owner[field].blank? && value.present? && value != false }
            owner.assign_attributes(fields)
            legacy = { proprietario_celular: owner.mobile_phone.presence || owner.phone_primary, proprietario_email: owner.email, proprietario_telefone_comercial: owner.business_phone, proprietario_telefone_residencial: owner.residential_phone }
            legacy.select! { |field, value| habitation[field].blank? && value.present? }
            result[:owner_fields] = fields.keys
            result[:property_fields] = legacy.keys
            if execute
              owner.save! if fields.any?
              habitation.update!(legacy) if legacy.any?
            end
          else
            result[:status] = "source_owner_missing_or_identity_mismatch"
          end
        end
      end
      puts(result.to_json)
      habitation.reload
    end
  end
end
