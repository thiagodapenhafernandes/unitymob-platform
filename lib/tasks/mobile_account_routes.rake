namespace :mobile do
  desc "Sincroniza (uma vez) todos os AdminUsers elegíveis com o gateway de discovery do app híbrido"
  task backfill_account_routes: :environment do
    registrar = Mobile::AccountRouteRegistrar.new

    unless registrar.configured?
      puts "[mobile:backfill_account_routes] GATEWAY_URL/GATEWAY_INTERNAL_TOKEN/PUBLIC_APP_URL não configurados neste servidor — nada a fazer."
      next
    end

    scope = AdminUser.where(super_admin: false)
    scope = scope.where(primary_admin_user_id: nil) if AdminUser.column_names.include?("primary_admin_user_id")

    total = scope.count
    processed = 0
    puts "[mobile:backfill_account_routes] sincronizando #{total} admin_users..."

    scope.find_each do |admin_user|
      processed += 1
      next if admin_user.tenant.blank? || admin_user.email.blank?

      registrar.sync!(admin_user)
      print "\r[mobile:backfill_account_routes] #{processed}/#{total}"
    end

    puts "\n[mobile:backfill_account_routes] concluído."
  end
end
