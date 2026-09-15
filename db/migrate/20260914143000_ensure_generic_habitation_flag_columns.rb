class EnsureGenericHabitationFlagColumns < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  RENAMES = {
    festival_salute_flag: :festival_flag,
    exibir_no_site_salute_flag: :exibir_no_site_portal_flag,
    salute_rental_management_flag: :rental_management_flag,
    salute_rental_management_answer: :rental_management_answer
  }.freeze

  def change
    RENAMES.each do |old_name, new_name|
      rename_column_if_needed(:habitations, old_name, new_name)
    end

    rename_index_if_needed(
      :habitations,
      :index_habitations_on_salute_rental_management_flag,
      :index_habitations_on_rental_management_flag
    )
  end

  private

  def rename_column_if_needed(table, old_name, new_name)
    return unless column_exists?(table, old_name)
    return if column_exists?(table, new_name)

    rename_column table, old_name, new_name
  end

  def rename_index_if_needed(table, old_name, new_name)
    return unless index_name_exists?(table, old_name)
    return if index_name_exists?(table, new_name)

    rename_index table, old_name, new_name
  end
end
