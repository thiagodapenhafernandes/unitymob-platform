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
      AttributeOption.find_or_create_by!(
        context: "habitation",
        category: "feature",
        name: name
      )
    end
  end

  def down
    AttributeOption.where(
      context: "habitation",
      category: "feature",
      name: FEATURE_NAMES
    ).destroy_all
  end
end
