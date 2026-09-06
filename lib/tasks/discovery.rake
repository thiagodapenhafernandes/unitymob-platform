namespace :discovery do
  desc 'Reconcile account memberships for one tenant (dry-run by default)'
  task reconcile: :environment do
    tenant = Tenant.find(ENV.fetch('TENANT_ID'))
    raise 'Configure DISCOVERY_* first' unless Mobile::AccountMembershipRegistrar.configured?
    count = tenant.admin_users.count
    puts "tenant_id=#{tenant.id} memberships=#{count} execute=#{ENV['EXECUTE'] == '1'}"
    if ENV['EXECUTE'] == '1'
      tenant.admin_users.find_each { |user| Mobile::SyncAccountMembershipJob.perform_later(user.id) }
    end
  end
end
