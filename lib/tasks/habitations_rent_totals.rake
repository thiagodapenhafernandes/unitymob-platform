namespace :habitations do
  desc "Zera total de aluguel quando nao existe aluguel base positivo"
  task backfill_rent_totals: :environment do
    scope = Habitation.where("COALESCE(valor_locacao_cents, 0) <= 0")
                      .where("COALESCE(valor_total_aluguel_cents, 0) <> 0")

    total = scope.count
    updated = scope.update_all(valor_total_aluguel_cents: 0, updated_at: Time.current)

    puts "Habitations corrigidos: #{updated}/#{total}"
  end
end
