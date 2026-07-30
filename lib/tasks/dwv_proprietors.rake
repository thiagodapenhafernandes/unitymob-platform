# Backfill do vínculo de proprietário para imóveis DWV.
#
#   bin/rails dwv:backfill_proprietors_from_constructors
#   bin/rails dwv:backfill_proprietors_from_constructors TENANT_ID=1
#   bin/rails dwv:backfill_proprietors_from_constructors TENANT_ID=1 EXECUTE=1
#
# Regra de negócio: imóvel DWV usa a construtora como proprietário.
namespace :dwv do
  desc "Preenche proprietário dos imóveis DWV a partir da construtora (DRY-RUN por padrão; EXECUTE=1 aplica)"
  task backfill_proprietors_from_constructors: :environment do
    execute = ENV["EXECUTE"] == "1"
    tenant_scope = ENV["TENANT_ID"].present? ? Tenant.where(id: ENV["TENANT_ID"]) : Tenant.all
    counters = Hash.new(0)

    tenant_scope.find_each do |tenant|
      Current.set(tenant: tenant) do
        scope = tenant.habitations.where(imovel_dwv: "Sim").where.not(construtora: [nil, ""])

        scope.find_each do |habitation|
          result = Dwv::ProprietorResolver.new(
            tenant: tenant,
            name: habitation.construtora,
            persist: execute
          ).call

          if result.action == :would_create
            counters[:would_create_proprietors] += 1
            puts "[dry] tenant=#{tenant.id} hab=#{habitation.id} codigo=#{habitation.codigo} criaria proprietário '#{habitation.construtora}'"
            next
          end

          proprietor = result.proprietor
          if proprietor.blank?
            counters[:ignored] += 1
            next
          end

          if habitation.proprietor_id == proprietor.id
            counters[:already_linked] += 1
            next
          end

          counters[:to_link] += 1
          puts "[#{execute ? 'exec' : 'dry'}] tenant=#{tenant.id} hab=#{habitation.id} codigo=#{habitation.codigo} proprietário #{habitation.proprietor_id || '-'} -> #{proprietor.id} (#{proprietor.name})"

          next unless execute

          habitation.update!(
            proprietor_id: proprietor.id,
            proprietario: proprietor.name,
            proprietario_codigo: proprietor.vista_code
          )
          counters[:linked] += 1
        end
      end
    end

    puts "-" * 60
    puts "#{execute ? 'EXECUTADO' : 'DRY-RUN'}"
    puts "a vincular: #{counters[:to_link]}"
    puts "vinculados: #{counters[:linked]}" if execute
    puts "já corretos: #{counters[:already_linked]}"
    puts "proprietários a criar: #{counters[:would_create_proprietors]}" unless execute
    puts "ignorados: #{counters[:ignored]}"
  end
end
