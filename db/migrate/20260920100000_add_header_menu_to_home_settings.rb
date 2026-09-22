class AddHeaderMenuToHomeSettings < ActiveRecord::Migration[7.1]
  # O modelo visual do site passa a ser uma escolha da conta: quem já dependia da
  # inferência por nome/slug recebe o valor inferido gravado, sem mudar o que o site mostra.
  class MigrationTenant < ActiveRecord::Base
    self.table_name = "tenants"
  end

  def up
    add_column :home_settings, :header_menu, :jsonb, null: false, default: []
    add_column :home_settings, :header_cta_label, :string
    add_column :home_settings, :header_cta_url, :string

    themes = %w[saluteimoveis conexaoimobiliaria]
    MigrationTenant.reset_column_information
    MigrationTenant.find_each do |tenant|
      inferred = [tenant.name, tenant.slug].filter_map { |value| value.to_s.parameterize.delete("-").presence }.find { |value| themes.include?(value) }
      tenant.update_columns(public_site_theme: inferred) if inferred
    end
  end

  def down
    remove_column :home_settings, :header_cta_url
    remove_column :home_settings, :header_cta_label
    remove_column :home_settings, :header_menu
  end
end
