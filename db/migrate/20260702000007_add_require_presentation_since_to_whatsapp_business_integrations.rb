class AddRequirePresentationSinceToWhatsappBusinessIntegrations < ActiveRecord::Migration[7.1]
  def change
    # Cutoff da exigência de apresentação: conversas criadas ANTES ficam isentas.
    add_column :whatsapp_business_integrations, :require_presentation_since, :datetime
  end
end
