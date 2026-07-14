class CompleteAiPropertyShareSettings < ActiveRecord::Migration[7.1]
  COLUMNS = {
    ai_property_search_selection_count_message: { type: :string, default: "%{count} selecionado(s)" },
    ai_property_search_share_button_label: { type: :string, default: "Compartilhar" },
    ai_property_search_link_copied_message: { type: :string, default: "Link copiado para compartilhar." },
    ai_property_search_share_error_message: { type: :string, default: "Não foi possível compartilhar." },
    ai_property_search_interest_error_message: { type: :string, default: "Não foi possível registrar o interesse." },
    ai_property_search_broker_event_meta: { type: :string, default: "%{count} imóvel(is) agrupado(s)" },
    ai_property_search_sharing_disabled_message: { type: :string, default: "Compartilhamento de seleções desativado." },
    ai_property_search_broker_events_limit: { type: :integer, default: 3 }
  }.freeze

  def up
    COLUMNS.each do |name, definition|
      next if column_exists?(:property_settings, name)

      add_column :property_settings, name, definition.fetch(:type), null: false, default: definition.fetch(:default)
    end
  end

  def down
    COLUMNS.each_key do |name|
      remove_column :property_settings, name if column_exists?(:property_settings, name)
    end
  end
end
