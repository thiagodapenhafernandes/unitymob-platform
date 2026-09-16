# Backfill pontual de fotos DWV para imóveis que vieram só com capa.
#
#   bin/rails dwv:backfill_single_photo_media
#   bin/rails dwv:backfill_single_photo_media TENANT_ID=1
#   bin/rails dwv:backfill_single_photo_media TENANT_ID=1 LIMIT=50 EXECUTE=1
namespace :dwv do
  desc "Atualiza fotos de imóveis DWV com até uma foto (DRY-RUN por padrão; EXECUTE=1 aplica)"
  task backfill_single_photo_media: :environment do
    execute = ENV["EXECUTE"] == "1"
    limit = ENV["LIMIT"].to_i
    tenant_scope = ENV["TENANT_ID"].present? ? Tenant.where(id: ENV["TENANT_ID"]) : Tenant.all
    counters = Hash.new(0)

    tenant_scope.find_each do |tenant|
      token = Setting.tenant_get("dwv_api_token", nil, tenant: tenant).to_s
      enabled = Setting.tenant_get("dwv_enabled", "false", tenant: tenant) == "true"
      unless enabled && token.present?
        counters[:tenants_skipped] += 1
        next
      end

      client = Dwv::Client.new(
        token: token,
        base_url: Setting.tenant_get("dwv_base_url", Dwv::SyncRunnerService::DEFAULT_BASE_URL, tenant: tenant)
      )

      scope = tenant.habitations.where(imovel_dwv: "Sim").where.not(codigo_dwv: [nil, ""])
      processed_for_tenant = 0

      scope.find_each do |habitation|
        next unless Array(habitation.pictures).size <= 1
        break if limit.positive? && processed_for_tenant >= limit

        counters[:candidates] += 1
        processed_for_tenant += 1

        if execute
          before_count = Array(habitation.pictures).size
          details = client.property_details(habitation.codigo_dwv)
          result = Dwv::PropertyImportService.new(details, tenant: tenant, refresh_media: true).perform
          after_count = Array(result.fetch(:habitation).reload.pictures).size
          counters[:updated] += 1 if after_count > before_count
          counters[:unchanged] += 1 if after_count <= before_count
          puts "[exec] tenant=#{tenant.id} hab=#{habitation.id} codigo=#{habitation.codigo} dwv=#{habitation.codigo_dwv} fotos #{before_count} -> #{after_count}"
        else
          counters[:would_fetch] += 1
          puts "[dry] tenant=#{tenant.id} hab=#{habitation.id} codigo=#{habitation.codigo} dwv=#{habitation.codigo_dwv} fotos=#{Array(habitation.pictures).size}"
        end
      rescue => e
        counters[:errors] += 1
        puts "[erro] tenant=#{tenant.id} hab=#{habitation.id} codigo=#{habitation.codigo} dwv=#{habitation.codigo_dwv}: #{e.class}: #{e.message}"
      end
    end

    puts "-" * 60
    puts "#{execute ? 'EXECUTADO' : 'DRY-RUN'}"
    puts "candidatos: #{counters[:candidates]}"
    puts "buscaria detalhes: #{counters[:would_fetch]}" unless execute
    puts "atualizados: #{counters[:updated]}" if execute
    puts "sem ganho: #{counters[:unchanged]}" if execute
    puts "tenants ignorados: #{counters[:tenants_skipped]}"
    puts "erros: #{counters[:errors]}"
  end
end
