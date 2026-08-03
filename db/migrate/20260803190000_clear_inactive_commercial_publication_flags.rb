class ClearInactiveCommercialPublicationFlags < ActiveRecord::Migration[7.1]
  INACTIVE_STATUS_SQL = "LOWER(unaccent(COALESCE(status, ''))) ~ '(suspenso|alugado|vendido|pendente)'".freeze
  PUBLICATION_COLUMNS = %i[
    exibir_no_site_flag
    exibir_no_site_salute_flag
    publicar_zapimoveis
    publicar_viva_real_vrsync
    publicar_imovelweb
    publicar_imovelweb_2
    publicar_chaves_na_mao
    publicar_casa_mineira
    publicar_lais_ai
    publicar_netimoveis_2
    publicar_loft
  ].freeze

  def up
    columns = PUBLICATION_COLUMNS.select { |column| column_exists?(:habitations, column) }
    return if columns.empty?

    updates = columns.index_with(false).merge(updated_at: Time.current)
    active_publication_sql = columns.map { |column| "#{column} = TRUE" }.join(" OR ")

    say_with_time "Clearing site and portal flags for inactive commercial statuses" do
      update_count = Class.new(ActiveRecord::Base) {
        self.table_name = "habitations"
      }.unscoped.where(INACTIVE_STATUS_SQL).where(active_publication_sql).update_all(updates)

      say "Updated #{update_count} habitations", true
    end
  end

  def down
    # Irreversible by design: we should not republish inactive commercial records.
  end
end
