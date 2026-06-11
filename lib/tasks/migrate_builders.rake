namespace :admin do
  desc "Migrate text-based constructors and developments to new models"
  task migrate_builders_and_developments: :environment do
    puts "Starting migration..."
    # Clear cache to ensure new columns are visible
    Habitation.connection.schema_cache.clear!
    Habitation.reset_column_information
    
    # 1. Migrate Constructors
    Habitation.where.not(construtora: [nil, ""]).where(constructor_id: nil).find_each do |h|
      constructor = Constructor.find_or_create_by!(name: h.construtora.strip)
      h.update_column(:constructor_id, constructor.id)
      print "."
    end
    puts "\nConstructors migrated."
    
    puts "\nMigration finished successfully!"
  end
end
