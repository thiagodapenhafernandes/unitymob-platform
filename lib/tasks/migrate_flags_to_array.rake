namespace :data do
  desc "Migrate legacy boolean flags to caracteristicas array"
  task migrate_flags_to_array: :environment do
    puts "Starting migration of flags to array..."
    
    Habitation.find_each do |h|
      features = h.caracteristicas.is_a?(Array) ? h.caracteristicas : []
      
      original_count = features.count
      
      features << 'Mobiliado' if h.mobiliado_flag && !features.include?('Mobiliado')
      features << 'Sem Mobília' if h.sem_mobilia_flag && !features.include?('Sem Mobília')
      features << 'Decorado' if h.decorado_flag && !features.include?('Decorado')
      features << 'Piscina Privativa' if h.piscina_flag && !features.include?('Piscina Privativa') && !features.include?('Piscina')
      features << 'Varanda Gourmet' if h.varanda_gourmet_flag && !features.include?('Varanda Gourmet')
      features << 'Garden' if h.garden_flag && !features.include?('Garden')
      features << 'Quadra Mar' if h.quadra_mar_flag && !features.include?('Quadra Mar')
      features << 'Frente Mar' if h.frente_mar_avenida_atlantica_flag && !features.include?('Frente Mar')
      
      # Map Vista Mar flags
      if (h.vista_frente_mar_flag) && !features.include?('Vista Mar') && !features.include?('Vista para o Mar')
        features << 'Vista Mar'
      end
      
      features << 'Aceita Financiamento' if h.aceita_financiamento_flag && !features.include?('Aceita Financiamento')
      features << 'Aceita Permuta' if h.aceita_permuta_flag && !features.include?('Aceita Permuta')
      features << 'Lavabo' if h.lavabo_flag && !features.include?('Lavabo')
      
      if features.count > original_count
        h.update_column(:caracteristicas, features.uniq.sort)
        print "."
      end
    end
    
    puts "\nMigration complete!"
  end
end
