class CreateCaptacoes < ActiveRecord::Migration[7.1]
  def change
    create_table :captacoes do |t|
      t.references :corretor, null: false, foreign_key: { to_table: :admin_users }
      t.string   :step,                default: "intro",  null: false
      t.boolean  :completed,           default: false,    null: false
      t.boolean  :published_on_site,   default: false,    null: false
      t.datetime :submitted_at

      t.integer :property_kind, null: false, default: 0   # enum residencial/sala_comercial/terreno
      t.integer :modalidade                                # enum venda/locacao_anual/ambos/locacao_diaria

      # Proprietário
      t.string :proprietario_nome
      t.string :proprietario_telefone
      t.string :proprietario_cpf_cnpj
      t.string :proprietario_email
      t.string :proprietario_cidade

      # Endereço
      t.string :zip_code
      t.string :street
      t.string :street_number
      t.string :neighborhood
      t.string :city
      t.string :state, limit: 2
      t.string :edificio_nome
      t.string :unidade_numero
      t.decimal :latitude,  precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6

      # Características
      t.integer :dormitorios
      t.integer :suites
      t.integer :demi_suites
      t.integer :salas
      t.integer :banheiros
      t.integer :vagas_garagem
      t.decimal :area_privativa, precision: 10, scale: 2
      t.decimal :area_total,     precision: 10, scale: 2
      t.string  :ocupacao
      t.string  :estado_imovel
      t.string  :situacao_imovel
      t.boolean :precisa_reforma,         default: false, null: false
      t.boolean :sacada,                  default: false, null: false
      t.boolean :terraco,                 default: false, null: false
      t.boolean :dependencia_empregada,   default: false, null: false
      t.integer :andares_total
      t.integer :aptos_por_andar
      t.decimal :distancia_praia, precision: 6, scale: 2

      # Features arrays
      t.string :caracteristicas_imovel, array: true, default: []
      t.string :caracteristicas_predio, array: true, default: []
      t.string :outras_taxas,           array: true, default: []
      t.string :aceita_permuta,         array: true, default: []
      t.string :dias_visitas,           array: true, default: []

      # Negociação
      t.decimal :valor_venda,      precision: 12, scale: 2
      t.decimal :valor_locacao,    precision: 10, scale: 2
      t.decimal :valor_condominio, precision: 10, scale: 2
      t.decimal :valor_iptu,       precision: 10, scale: 2
      t.decimal :saldo_devedor,    precision: 12, scale: 2
      t.string  :cidade_permuta
      t.string  :aceita_parcelamento
      t.string  :motivo_venda

      # Visitas
      t.string :chaves_com
      t.string :senha_imovel
      t.string :senha_portaria

      t.text :observacoes

      # Extras (específico por tipo)
      t.jsonb :extras, default: {}, null: false

      t.timestamps
    end

    add_index :captacoes, [:corretor_id, :completed]
    add_index :captacoes, :property_kind
    add_index :captacoes, :modalidade
    add_index :captacoes, :published_on_site
    add_index :captacoes, :submitted_at
    add_index :captacoes, :caracteristicas_imovel, using: :gin
    add_index :captacoes, :caracteristicas_predio, using: :gin
  end
end
