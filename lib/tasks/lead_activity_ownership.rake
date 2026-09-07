namespace :lead_activities do
  desc "Reconcilia responsáveis de pendências com o lead (dry-run; TENANT_ID obrigatório)"
  task reconcile_owners: :environment do
    tenant = Tenant.find(Integer(ENV.fetch("TENANT_ID")))
    execute = ENV["EXECUTE"] == "1"
    backup = File.open(ENV.fetch("BACKUP_PATH"), "wx", 0o600) if execute
    counts = { tasks: 0, appointments: 0, leads: 0 }

    Current.set(tenant: tenant) do
      task_leads = tenant.tasks.pendentes.joins(:lead)
                         .where("leads.tenant_id = tasks.tenant_id AND tasks.admin_user_id IS DISTINCT FROM leads.admin_user_id")
                         .select(:lead_id)
      appointment_leads = tenant.appointments.where(status: "agendado").joins(:lead)
                                .where("leads.tenant_id = appointments.tenant_id AND appointments.admin_user_id IS DISTINCT FROM leads.admin_user_id")
                                .select(:lead_id)
      tenant.leads.where(id: task_leads).or(tenant.leads.where(id: appointment_leads))
            .joins(:admin_user).where(admin_users: { tenant_id: tenant.id }).find_each do |lead|
        reconcile = lambda do
          next if lead.admin_user_id.blank? || lead.admin_user.tenant_id != tenant.id

          rows = {
            tasks: lead.tasks.where(tenant_id: tenant.id, status: "pendente").where("admin_user_id IS DISTINCT FROM ?", lead.admin_user_id).pluck(:id, :admin_user_id, :updated_at),
            appointments: lead.appointments.where(tenant_id: tenant.id, status: "agendado").where("admin_user_id IS DISTINCT FROM ?", lead.admin_user_id).pluck(:id, :admin_user_id, :updated_at)
          }
          next if rows.values.all?(&:empty?)

          counts[:leads] += 1
          rows.each { |type, records| counts[type] += records.length }
          if execute
            backup.puts({ tenant_id: tenant.id, lead_id: lead.id, target_admin_user_id: lead.admin_user_id, before: rows }.to_json)
            backup.flush
            backup.fsync
            lead.sync_open_activity_owners!
          end
        end
        execute ? lead.with_lock(&reconcile) : reconcile.call
      end
    end
    puts({ tenant_id: tenant.id, execute: execute, counts: counts }.to_json)
  ensure
    backup&.close
  end
end
