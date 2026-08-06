class BackfillHomeSectionLegacyTypeFilters < ActiveRecord::Migration[7.1]
  LEGACY_FILTERS = {
    3 => "destaque_web",
    4 => "preco_reduzido",
    5 => "empreendimentos",
    6 => "locacao"
  }.freeze

  def up
    return unless table_exists?(:home_sections) && column_exists?(:home_sections, :property_filters)

    LEGACY_FILTERS.each do |section_type, filter_key|
      execute <<~SQL.squish
        UPDATE home_sections
           SET property_filters = COALESCE(property_filters, '{}'::jsonb) || jsonb_build_object(#{quote(filter_key)}, '1'),
               updated_at = CURRENT_TIMESTAMP
         WHERE section_type = #{section_type}
           AND NOT (COALESCE(property_filters, '{}'::jsonb) ? #{quote(filter_key)})
      SQL
    end
  end

  def down
    # Nao removemos filtros porque eles podem ter sido ajustados manualmente apos a migracao.
  end
end
