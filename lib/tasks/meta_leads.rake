namespace :meta_leads do
  desc "Reconcilia imovel de interesse de leads Meta pelo codigo no nome do formulario. Use EXECUTE=1 para gravar."
  task reconcile_property_interests: :environment do
    tenant = Tenant.find_by(id: ENV["TENANT_ID"]) if ENV["TENANT_ID"].present?
    abort "Informe TENANT_ID." if tenant.blank?

    execute = ENV["EXECUTE"].to_s == "1"
    operational_only = ENV["OPERATIONAL_ONLY"].to_s == "1"
    non_operational_statuses = Lead.non_operational_status_values(tenant:)
    result = {
      mode: execute ? "execute" : "dry_run",
      tenant_id: tenant.id,
      operational_only: operational_only,
      scanned: 0,
      linked: 0,
      skipped: 0,
      skipped_non_operational: 0,
      unmapped: 0
    }

    Current.set(tenant:) do
      tenant.leads.where(property_id: nil).find_each(batch_size: 500) do |lead|
        begin
          info = lead.other_information.to_h
          next unless lead.origin.to_s.match?(/facebook|instagram|meta/i) ||
            lead.attribution_channel.to_s == "meta_ads" ||
            info["meta_leadgen_id"].present?

          result[:scanned] += 1

          if operational_only && non_operational_statuses.include?(lead.status)
            result[:skipped_non_operational] += 1
            next
          end

          property = MetaLeadProcessingJob.property_from_text(tenant, lead.product)
          if property.blank?
            result[:unmapped] += 1
            next
          end

          if execute
            lead.update!(property_id: property.id)
            lead.property_interests.find_or_create_by!(habitation: property) do |interest|
              interest.tenant = tenant
            end
          end

          result[:linked] += 1
        rescue
          result[:skipped] += 1
        end
      end
    end

    puts result.to_json
  end
end
