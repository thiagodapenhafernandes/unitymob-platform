class ClearUnlinkedStandaloneDevelopmentNames < ActiveRecord::Migration[7.0]
  class MigrationHabitation < ActiveRecord::Base
    self.table_name = "habitations"
  end

  STANDALONE_CATEGORIES_WITHOUT_DEVELOPMENT_NAME = [
    "Apartamento",
    "Casa",
    "Casa em Condomínio",
    "Cobertura",
    "Sobrado",
    "Loft",
    "Studio",
    "Sala Comercial",
    "Loja",
    "Prédio Comercial",
    "Galpão"
  ].freeze

  def up
    MigrationHabitation
      .where.not(tipo: "Empreendimento")
      .where(categoria: STANDALONE_CATEGORIES_WITHOUT_DEVELOPMENT_NAME)
      .where(codigo_empreendimento: [nil, ""])
      .where.not(nome_empreendimento: [nil, ""])
      .update_all(nome_empreendimento: nil, updated_at: Time.current)
  end

  def down
    # The previous standalone development names were imported data and cannot be restored safely.
  end
end
