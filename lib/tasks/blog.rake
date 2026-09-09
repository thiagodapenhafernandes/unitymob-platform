namespace :blog do
  desc "Importa backup WordPress para uma conta (TENANT_SLUG, BACKUP; EXECUTE=1 para gravar)"
  task import_wordpress: :environment do
    tenant = Tenant.find_by!(slug: ENV.fetch("TENANT_SLUG"))
    result = Blog::WordpressImporter.new(tenant: tenant, path: ENV.fetch("BACKUP")).call(execute: ENV["EXECUTE"] == "1")
    puts JSON.pretty_generate(result)
  end
end
