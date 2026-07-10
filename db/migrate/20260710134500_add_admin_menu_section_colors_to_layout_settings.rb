class AddAdminMenuSectionColorsToLayoutSettings < ActiveRecord::Migration[7.1]
  DEFAULTS = {
    product: { background_color: "#2563EB", background_opacity: 30, text_color: "#2563EB", border_color: "#2563EB" },
    operation: { background_color: "#0F766E", background_opacity: 30, text_color: "#0F766E", border_color: "#0F766E" },
    management: { background_color: "#7C3AED", background_opacity: 30, text_color: "#7C3AED", border_color: "#7C3AED" },
    growth: { background_color: "#DB2777", background_opacity: 30, text_color: "#DB2777", border_color: "#DB2777" },
    public_site: { background_color: "#0891B2", background_opacity: 30, text_color: "#0891B2", border_color: "#0891B2" },
    integrations: { background_color: "#D97706", background_opacity: 30, text_color: "#D97706", border_color: "#D97706" },
    settings: { background_color: "#64748B", background_opacity: 30, text_color: "#64748B", border_color: "#64748B" },
    account: { background_color: "#475569", background_opacity: 30, text_color: "#475569", border_color: "#475569" }
  }.freeze

  def change
    add_column :layout_settings, :admin_menu_section_colors, :jsonb, default: DEFAULTS, null: false unless column_exists?(:layout_settings, :admin_menu_section_colors)
  end
end
