namespace :habitations do
  desc "Reconcilia nomes de empreendimento pontuais em imóveis sem nome/código. Use APPLY=true para gravar."
  task reconcile_missing_development_names: :environment do
    apply = ActiveModel::Type::Boolean.new.cast(ENV.fetch("APPLY", "false"))
    tenant_id = ENV.fetch("TENANT_ID", Tenant.default.id).to_i
    tenant = Tenant.find(tenant_id)

    service = Habitations::DevelopmentNameReconciliationService.new(
      tenant: tenant,
      dry_run: !apply
    ).call

    puts "[habitations development reconcile] tenant=#{tenant.id} apply=#{apply}"
    service.results.each do |result|
      details = [
        "codigo=#{result.codigo}",
        "status=#{result.status}",
        "before_name=#{result.before_name.inspect}",
        "before_code=#{result.before_code.inspect}",
        "after_name=#{result.after_name.inspect}"
      ]
      details << "message=#{result.message.inspect}" if result.message.present?
      puts "  - #{details.join(' | ')}"
    end
    puts "[habitations development reconcile] stats=#{service.stats.inspect}"
    puts "[habitations development reconcile] DRY_RUN ativo. Use APPLY=true para gravar." unless apply
  end
end
