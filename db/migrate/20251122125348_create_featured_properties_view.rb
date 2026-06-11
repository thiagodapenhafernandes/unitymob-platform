class CreateFeaturedPropertiesView < ActiveRecord::Migration[7.1]
  def up
    # Criar materialized view para imóveis em destaque
    # Isso cacheia queries complexas e melhora significativamente a performance
    execute <<-SQL
      CREATE MATERIALIZED VIEW featured_properties_view AS
      SELECT 
        id,
        codigo,
        slug,
        categoria,
        status,
        cidade,
        bairro,
        titulo_anuncio,
        valor_venda_cents,
        valor_locacao_cents,
        dormitorios_qtd,
        suites_qtd,
        vagas_qtd,
        area_total_m2,
        pictures,
        destaque_web_flag,
        lancamento_flag,
        data_atualizacao_crm,
        updated_at
      FROM habitations
      WHERE exibir_no_site_flag = true
        AND destaque_web_flag = true
        AND (status = 'Venda' OR status = 'Locação')
      ORDER BY data_atualizacao_crm DESC NULLS LAST
      LIMIT 100;
    SQL
    
    # Criar índice na view materializada para melhor performance
    add_index :featured_properties_view, :id, unique: true
    add_index :featured_properties_view, :categoria
    add_index :featured_properties_view, :cidade
  end
  
  def down
    execute "DROP MATERIALIZED VIEW IF EXISTS featured_properties_view;"
  end
end
