class AddAiPropertyShareSettingsToPropertySettings < ActiveRecord::Migration[7.1]
  def change
    change_table :property_settings, bulk: true do |t|
      t.boolean :ai_property_search_sharing_enabled, null: false, default: true
      t.integer :ai_property_search_share_max_properties, null: false, default: 20
      t.integer :ai_property_search_share_expiration_days, null: false, default: 30
      t.integer :ai_property_search_visitor_recognition_days, null: false, default: 365
      t.string :ai_property_search_share_title, null: false, default: "Imóveis selecionados"
      t.string :ai_property_search_share_message, null: false, default: "Separei %{count} imóveis para você."
      t.string :ai_property_search_public_eyebrow, null: false, default: "Seleção preparada para você"
      t.string :ai_property_search_public_title, null: false, default: "%{count} imóvel(is) selecionado(s)"
      t.string :ai_property_search_public_description, null: false, default: "Veja os detalhes e marque os imóveis que realmente despertaram seu interesse."
      t.string :ai_property_search_view_property_label, null: false, default: "Ver imóvel"
      t.string :ai_property_search_interest_button_label, null: false, default: "Tenho interesse"
      t.string :ai_property_search_identity_title, null: false, default: "Como podemos identificar você?"
      t.string :ai_property_search_identity_description, null: false, default: "Informe uma vez. Nos próximos imóveis, seu interesse será enviado diretamente ao corretor."
      t.string :ai_property_search_identity_name_label, null: false, default: "Nome"
      t.string :ai_property_search_identity_phone_label, null: false, default: "WhatsApp"
      t.string :ai_property_search_identity_submit_label, null: false, default: "Enviar interesse"
      t.string :ai_property_search_identity_cancel_label, null: false, default: "Cancelar"
      t.string :ai_property_search_interest_success_message, null: false, default: "Interesse enviado ao corretor."
      t.string :ai_property_search_lead_origin, null: false, default: "Seleção compartilhada"
      t.string :ai_property_search_broker_panel_title, null: false, default: "Interesses nas suas seleções"
      t.string :ai_property_search_broker_event_message, null: false, default: "%{name} demonstrou interesse"
      t.string :ai_property_search_selection_count_message, null: false, default: "%{count} selecionado(s)"
      t.string :ai_property_search_share_button_label, null: false, default: "Compartilhar"
      t.string :ai_property_search_link_copied_message, null: false, default: "Link copiado para compartilhar."
      t.string :ai_property_search_share_error_message, null: false, default: "Não foi possível compartilhar."
      t.string :ai_property_search_interest_error_message, null: false, default: "Não foi possível registrar o interesse."
      t.string :ai_property_search_broker_event_meta, null: false, default: "%{count} imóvel(is) agrupado(s)"
      t.string :ai_property_search_sharing_disabled_message, null: false, default: "Compartilhamento de seleções desativado."
      t.integer :ai_property_search_broker_events_limit, null: false, default: 3
    end
  end
end
