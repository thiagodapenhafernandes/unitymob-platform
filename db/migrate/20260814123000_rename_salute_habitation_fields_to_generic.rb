class RenameSaluteHabitationFieldsToGeneric < ActiveRecord::Migration[7.1]
  def change
    rename_column_if_exists :habitations, :festival_salute_flag, :festival_flag
    rename_column_if_exists :habitations, :exibir_no_site_salute_flag, :exibir_no_site_portal_flag
    rename_column_if_exists :habitations, :salute_rental_management_flag, :rental_management_flag
    rename_column_if_exists :habitations, :salute_rental_management_answer, :rental_management_answer

    rename_index_if_exists :habitations,
                           :index_habitations_on_salute_rental_management_flag,
                           :index_habitations_on_rental_management_flag

    normalize_home_section_filter_keys if column_exists?(:home_sections, :property_filters)
  end

  private

  def normalize_home_section_filter_keys
    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE home_sections
             SET property_filters = property_filters - 'administracao_locacao_salute' || jsonb_build_object('administracao_locacao', property_filters->'administracao_locacao_salute')
           WHERE property_filters ? 'administracao_locacao_salute'
             AND NOT property_filters ? 'administracao_locacao'
        SQL

        execute <<~SQL.squish
          UPDATE home_sections
             SET property_filters = property_filters - 'administracao_locacao_salute'
           WHERE property_filters ? 'administracao_locacao_salute'
        SQL

        execute <<~SQL.squish
          UPDATE home_sections
             SET property_filters = property_filters - 'exibir_site_salute' || jsonb_build_object('exibir_no_site', property_filters->'exibir_site_salute')
           WHERE property_filters ? 'exibir_site_salute'
             AND NOT property_filters ? 'exibir_no_site'
        SQL

        execute <<~SQL.squish
          UPDATE home_sections
             SET property_filters = property_filters - 'exibir_site_salute'
           WHERE property_filters ? 'exibir_site_salute'
        SQL
      end
    end
  end

  def rename_column_if_exists(table, old_name, new_name)
    return unless column_exists?(table, old_name)
    return if column_exists?(table, new_name)

    rename_column table, old_name, new_name
  end

  def rename_index_if_exists(table, old_name, new_name)
    return unless index_name_exists?(table, old_name)
    return if index_name_exists?(table, new_name)

    rename_index table, old_name, new_name
  end
end
