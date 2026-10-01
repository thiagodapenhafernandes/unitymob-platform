# Layouts do hero da home (Clássico, Barra, Cartão), posição horizontal da busca e busca por descrição/voz com IA.
# Tudo aditivo: o padrão (classic) é exatamente o hero de hoje.
class AddHeroLayoutToHomeSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :home_settings, :hero_layout, :string, null: false, default: "classic"
    add_column :home_settings, :hero_search_align, :string, null: false, default: "center"
    add_column :home_settings, :hero_ai_search_enabled, :boolean, null: false, default: false
    add_column :home_settings, :hero_ai_suggestions, :text
    add_check_constraint :home_settings, "hero_layout IN ('classic', 'bar', 'card')", name: "home_settings_hero_layout_valid"
    add_check_constraint :home_settings, "hero_search_align IN ('left', 'center', 'right')", name: "home_settings_hero_search_align_valid"
  end
end
