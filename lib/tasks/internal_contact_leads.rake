namespace :leads do
  namespace :internal_contacts do
    desc "Lista ou remove leads cujo telefone pertence a usuarios internos da conta. Use EXECUTE=1 para remover."
    task purge: :environment do
      execute = ENV["EXECUTE"].to_s == "1"
      tenant_filter = ENV["TENANT"].to_s.strip.presence
      tenant = Tenant.find_by(slug: tenant_filter) || Tenant.find_by(id: tenant_filter) if tenant_filter.present?

      abort "TENANT=#{tenant_filter} nao encontrado" if tenant_filter.present? && tenant.blank?

      results = Leads::InternalContactCleanup.call(tenant: tenant, execute: execute, logger: Rails.logger)
      total_matched = 0
      total_removed = 0

      results.each do |result|
        total_matched += result.matched_count
        total_removed += result.removed_count
        next if result.matched_count.zero?

        puts "Tenant ##{result.tenant_id} #{result.tenant_name}: #{result.matched_count} lead(s) encontrado(s), #{result.removed_count} removido(s)"
        result.leads.each do |lead|
          puts "  - Lead ##{lead[:id]} | #{lead[:name]} | #{lead[:phone]} | #{lead[:origin]} | corretor_id=#{lead[:admin_user_id]} | #{lead[:created_at]}"
        end
      end

      puts "Total encontrado: #{total_matched}"
      puts "Total removido: #{total_removed}"
      puts "Dry-run: nenhum lead foi removido. Rode com EXECUTE=1 para remover." unless execute
    end
  end
end
