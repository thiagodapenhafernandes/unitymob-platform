# frozen_string_literal: true

# PostGIS instala várias tabelas/views internas (spatial_ref_sys,
# geography_columns, geometry_columns, etc.) que não devem ir para o
# db/schema.rb — elas são recriadas automaticamente pelo enable_extension.
# Sem isso, db:schema:load tenta criar spatial_ref_sys e conflita com a
# tabela já criada pelo CREATE EXTENSION postgis.
Rails.application.config.after_initialize do
  ActiveRecord::SchemaDumper.ignore_tables += [
    "spatial_ref_sys",
    "geography_columns",
    "geometry_columns"
  ]
end
