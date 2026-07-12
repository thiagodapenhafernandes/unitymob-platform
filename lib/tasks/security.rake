namespace :security do
  desc "Executa o contrato crítico de isolamento multi-tenant"
  task tenant_isolation: :environment do
    specs = %w[
      spec/models/tenant_global_content_isolation_spec.rb
      spec/requests/admin/tenant_direct_uploads_spec.rb
      spec/requests/admin/access_security_spec.rb
      spec/requests/admin/system_spec.rb
      spec/requests/integrations/portal_feeds_spec.rb
    ]

    command = [Gem.ruby, "-S", "bundle", "exec", "rspec", *specs]
    abort "Falha no contrato de isolamento multi-tenant" unless system(*command)
  end
end
