class AddVistaFieldsToHabitations < ActiveRecord::Migration[7.1]
  def change
    # Address Details
    add_column :habitations, :bairro_comercial, :string
    add_column :habitations, :bloco, :string
    add_column :habitations, :lote, :string
    add_column :habitations, :imediacoes, :text
    
    # Property Details
    add_column :habitations, :banheiro_social_qtd, :integer
    add_column :habitations, :decorado_flag, :boolean
    add_column :habitations, :aptos_andar, :integer
    add_column :habitations, :aptos_edificio, :integer
    add_column :habitations, :garden_flag, :boolean
    add_column :habitations, :quadra_mar_flag, :boolean
    add_column :habitations, :sem_mobilia_flag, :boolean
    
    # Financial
    add_column :habitations, :valor_venda_anterior_cents, :integer
    add_column :habitations, :valor_total_aluguel_cents, :integer
    add_column :habitations, :valor_promocional_cents, :integer
    
    # Property Information
    add_column :habitations, :construtora, :string
    add_column :habitations, :proprietario, :string
    add_column :habitations, :inscricao_imobiliaria, :string
    add_column :habitations, :descricao_empreendimento, :text
    add_column :habitations, :caracteristica_unica, :text
    
    # Location Highlights (Boolean Flags)
    add_column :habitations, :terceira_avenida_flag, :boolean
    add_column :habitations, :arriba_flag, :boolean
    add_column :habitations, :avenida_brasil_flag, :boolean
    add_column :habitations, :bairro_fazenda_itajai_flag, :boolean
    add_column :habitations, :balneario_picarras_flag, :boolean
    add_column :habitations, :barra_flag, :boolean
    add_column :habitations, :barra_norte_flag, :boolean
    add_column :habitations, :barra_sul_flag, :boolean
    add_column :habitations, :cabecudas_flag, :boolean
    add_column :habitations, :camboriu_flag, :boolean
    add_column :habitations, :centro_flag, :boolean
    add_column :habitations, :estaleirinho_flag, :boolean
    add_column :habitations, :frente_mar_avenida_atlantica_flag, :boolean
    add_column :habitations, :itajai_flag, :boolean
    add_column :habitations, :itapema_flag, :boolean
    add_column :habitations, :nacoes_flag, :boolean
    add_column :habitations, :pioneiros_flag, :boolean
    add_column :habitations, :praia_brava_flag, :boolean
    add_column :habitations, :praia_dos_amores_flag, :boolean
    add_column :habitations, :vista_frente_mar_flag, :boolean
    
    # Site Flags
    add_column :habitations, :festival_salute_flag, :boolean
    add_column :habitations, :exibir_no_site_salute_flag, :boolean
    
    # Configuration
    add_column :habitations, :categoria_grupo, :string
    add_column :habitations, :data_entrega, :date
    add_column :habitations, :tour_virtual, :string
    add_column :habitations, :fotos_empreendimento, :jsonb
    
    # Agent/Broker
    add_column :habitations, :codigo_corretor, :string
    add_column :habitations, :captador_account_id, :string
    add_column :habitations, :agenciador, :string
    add_column :habitations, :codigo_dwv, :string
    add_column :habitations, :imovel_dwv, :string
    add_column :habitations, :tem_placa_flag, :boolean
    
    # Add indexes for commonly queried location flags
    add_index :habitations, :centro_flag
    add_index :habitations, :praia_brava_flag
    add_index :habitations, :quadra_mar_flag
    add_index :habitations, :frente_mar_avenida_atlantica_flag
  end
end
