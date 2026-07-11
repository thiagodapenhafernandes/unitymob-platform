class PromoteAdminMenuSectionStyleDefaults < ActiveRecord::Migration[7.1]
  PRESET = {
    product: { background_color: "#E8F0FB", background_opacity: 100, text_color: "#245486", border_color: "#C7D8EE", box_shadow: "inset 2px 0 0 #365F8F" },
    operation: { background_color: "#EBFFFE", background_opacity: 100, text_color: "#0F766E", border_color: "#C9EEEB", box_shadow: "inset 2px 0 0 #0F766E" },
    management: { background_color: "#ECE0FF", background_opacity: 100, text_color: "#7C3AED", border_color: "#D2C0F2", box_shadow: "inset 2px 0 0 #365F8F" },
    growth: { background_color: "#DB2777", background_opacity: 10, text_color: "#DB2777", border_color: "#ECC1D4", box_shadow: "inset 2px 0 0 #365F8F" },
    public_site: { background_color: "#0891B2", background_opacity: 10, text_color: "#0891B2", border_color: "#BDDDE5", box_shadow: "inset 2px 0 0 #365F8F" },
    integrations: { background_color: "#D97706", background_opacity: 10, text_color: "#D97706", border_color: "#E2D0BB", box_shadow: "inset 2px 0 0 #365F8F" },
    settings: { background_color: "#64748B", background_opacity: 10, text_color: "#64748B", border_color: "#AFC3DE", box_shadow: "inset 2px 0 0 #365F8F" },
    account: { background_color: "#475569", background_opacity: 10, text_color: "#475569", border_color: "#B0C1D8", box_shadow: "inset 2px 0 0 #365F8F" }
  }.freeze

  PREVIOUS_DEFAULT = {
    product: { background_color: "#2563EB", background_opacity: 30, text_color: "#2563EB", border_color: "#2563EB" },
    operation: { background_color: "#0F766E", background_opacity: 30, text_color: "#0F766E", border_color: "#0F766E" },
    management: { background_color: "#7C3AED", background_opacity: 30, text_color: "#7C3AED", border_color: "#7C3AED" },
    growth: { background_color: "#DB2777", background_opacity: 30, text_color: "#DB2777", border_color: "#DB2777" },
    public_site: { background_color: "#0891B2", background_opacity: 30, text_color: "#0891B2", border_color: "#0891B2" },
    integrations: { background_color: "#D97706", background_opacity: 30, text_color: "#D97706", border_color: "#D97706" },
    settings: { background_color: "#64748B", background_opacity: 30, text_color: "#64748B", border_color: "#64748B" },
    account: { background_color: "#475569", background_opacity: 30, text_color: "#475569", border_color: "#475569" }
  }.freeze

  def up
    change_column_default :layout_settings, :admin_menu_section_colors, from: PREVIOUS_DEFAULT, to: PRESET
    execute "UPDATE layout_settings SET admin_menu_section_colors = #{connection.quote(PRESET.to_json)}::jsonb"
  end

  def down
    change_column_default :layout_settings, :admin_menu_section_colors, from: PRESET, to: PREVIOUS_DEFAULT
    execute "UPDATE layout_settings SET admin_menu_section_colors = #{connection.quote(PREVIOUS_DEFAULT.to_json)}::jsonb"
  end
end
