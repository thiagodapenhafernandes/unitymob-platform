require Rails.root.join("lib/admin/ui_contract_verifier")

namespace :admin do
  desc "Verifica contrato UI das areas admin migradas"
  task verify_ui_contract: :environment do
    verifier = Admin::UiContractVerifier.new

    if verifier.valid?
      puts "admin:verify_ui_contract OK"
      next
    end

    puts "admin:verify_ui_contract encontrou #{verifier.violations.size} problema(s):"
    verifier.violations.each do |violation|
      puts " - #{violation}"
    end

    abort("Falha no contrato UI do admin")
  end
end
