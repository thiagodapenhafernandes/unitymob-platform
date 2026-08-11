class SeedMissingHabitationFeatureOptions < ActiveRecord::Migration[7.1]
  FEATURE_NAMES = [
    "Churrasqueira à gás",
    "Churrasqueira à carvão",
    "Diferenciado",
    "Duplex",
    "Frente Mar",
    "Garden",
    "Hall Entrada",
    "Mobiliado Decorado",
    "Quadra Mar",
    "Sem Mobília",
    "Triplex"
  ].freeze

  def up
    FEATURE_NAMES.each do |name|
      next if select_value(<<~SQL.squish)
        SELECT 1
          FROM attribute_options
         WHERE context = 'habitation'
           AND category = 'feature'
           AND lower(name) = lower(#{connection.quote(name)})
         LIMIT 1
      SQL

      execute(<<~SQL.squish)
        INSERT INTO attribute_options (context, category, name, created_at, updated_at)
        VALUES ('habitation', 'feature', #{connection.quote(name)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
    end
  end

  def down
    quoted_names = FEATURE_NAMES.map { |name| connection.quote(name) }.join(", ")

    execute(<<~SQL.squish)
      DELETE FROM attribute_options
       WHERE context = 'habitation'
         AND category = 'feature'
         AND name IN (#{quoted_names})
    SQL
  end
end
