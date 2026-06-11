class CreateHabitations < ActiveRecord::Migration[7.1]
  def change
    create_table :habitations do |t|
      # Identificação única e slug para URLs amigáveis
      t.string :codigo, null: false
      t.string :slug
      
      # Informações básicas do imóvel
      t.string :categoria # Apartamento, Casa, Terreno, etc.
      t.string :status # Venda, Locação, Novo, Lançamento, etc.
      t.string :situacao # Disponível, Vendido, Alugado, etc.
      t.string :tipo # Unitário, Empreendimento, etc.
      
      # Dados do empreendimento (se aplicável)
      t.string :codigo_empreendimento
      t.string :nome_empreendimento
      
      # Endereço completo
      t.string :tipo_endereco # Rua, Avenida, etc.
      t.string :endereco
      t.string :numero
      t.string :complemento
      t.string :bairro
      t.string :cidade
      t.string :uf, limit: 2
      t.string :cep, limit: 10
      t.string :pais, default: 'Brasil'
      
      # Geolocalização
      t.decimal :latitude, precision: 10, scale: 7
      t.decimal :longitude, precision: 10, scale: 7
      
      # Características principais
      t.integer :dormitorios_qtd, default: 0
      t.integer :suites_qtd, default: 0
      t.integer :banheiros_qtd, default: 0
      t.integer :vagas_qtd, default: 0
      t.integer :elevadores_qtd, default: 0
      
      # Áreas (em m²)
      t.decimal :area_privativa_m2, precision: 10, scale: 2
      t.decimal :area_total_m2, precision: 10, scale: 2
      t.decimal :area_terreno_m2, precision: 10, scale: 2
      t.decimal :area_util_m2, precision: 10, scale: 2
      
      # Valores monetários (armazenados em centavos para precisão)
      t.bigint :valor_venda_cents
      t.bigint :valor_locacao_cents
      t.bigint :valor_condominio_cents
      t.bigint :valor_iptu_cents
      t.bigint :valor_por_m2_cents
      
      # Campos JSONB para dados flexíveis
      t.jsonb :caracteristicas, default: {}
      t.jsonb :infra_estrutura, default: {}
      t.jsonb :destaque_localizacao, default: {}
      t.jsonb :pictures, default: []
      t.jsonb :videos, default: []
      t.jsonb :plantas, default: []
      
      # Textos e descrições
      t.text :descricao_web
      t.text :descricao_interna
      t.string :titulo_anuncio
      t.text :observacoes
      
      # Informações do proprietário/corretor
      t.string :corretor_nome
      t.string :corretor_telefone
      t.string :corretor_email
      t.string :proprietario_codigo
      
      # Flags de controle
      t.boolean :exibir_no_site_flag, default: false
      t.boolean :destaque_web_flag, default: false
      t.boolean :lancamento_flag, default: false
      t.boolean :aceita_permuta_flag, default: false
      t.boolean :aceita_financiamento_flag, default: false
      t.boolean :mobiliado_flag, default: false
      
      # Dados de sincronização com Vista Soft
      t.datetime :data_atualizacao_crm
      t.datetime :data_cadastro_crm
      t.string :status_vista
      
      # Campos para SEO
      t.string :meta_title
      t.text :meta_description
      t.string :meta_keywords
      
      # Timestamps do Rails
      t.timestamps
    end
    
    # Índices únicos
    add_index :habitations, :codigo, unique: true
    add_index :habitations, :slug, unique: true
    
    # Índices compostos para queries mais comuns (melhor performance)
    add_index :habitations, [:status, :categoria, :cidade], 
              name: 'idx_habitations_status_categoria_cidade'
    add_index :habitations, [:exibir_no_site_flag, :status], 
              name: 'idx_habitations_exibir_status'
    add_index :habitations, [:cidade, :bairro, :status],
              name: 'idx_habitations_localizacao_status'
    add_index :habitations, [:categoria, :status],
              name: 'idx_habitations_categoria_status'
    
    # Índices para ordenação e filtros de preço
    add_index :habitations, :valor_venda_cents
    add_index :habitations, :valor_locacao_cents
    add_index :habitations, [:valor_venda_cents, :status],
              name: 'idx_habitations_venda_status'
    
    # Índices para características específicas
    add_index :habitations, :dormitorios_qtd
    add_index :habitations, :vagas_qtd
    add_index :habitations, :area_total_m2
    
    # Índices GIN para campos JSONB (buscas dentro do JSON)
    add_index :habitations, :caracteristicas, using: :gin
    add_index :habitations, :infra_estrutura, using: :gin
    add_index :habitations, :destaque_localizacao, using: :gin
    add_index :habitations, :pictures, using: :gin
    
    # Índices para geolocalização (futuras buscas por proximidade)
    add_index :habitations, [:latitude, :longitude],
              name: 'idx_habitations_geolocation'
    
    # Índices para flags mais usadas
    add_index :habitations, :destaque_web_flag
    add_index :habitations, :lancamento_flag
    
    # Índice para empreendimentos
    add_index :habitations, :codigo_empreendimento
    
    # Índices para datas (ordenação por atualização)
    add_index :habitations, :data_atualizacao_crm
    add_index :habitations, :created_at
    add_index :habitations, :updated_at
  end
end
