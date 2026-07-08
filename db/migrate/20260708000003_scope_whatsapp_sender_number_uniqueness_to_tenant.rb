class ScopeWhatsappSenderNumberUniquenessToTenant < ActiveRecord::Migration[7.1]
  # phone_number_id era UNIQUE GLOBAL: duas contas jamais poderiam registrar o
  # MESMO número da Meta — mas no modelo agência cada tenant tem seu próprio WABA,
  # e um mesmo phone_number_id só colide dentro do mesmo tenant. Troca o UNIQUE
  # global por UNIQUE (tenant_id, phone_number_id). tenant_id já existe e é
  # NOT NULL (migration 20260628235800), então nenhuma linha fica órfã.
  def up
    # Salvaguarda: não deve haver colisão (tenant_id, phone_number_id), mas se
    # houver a criação do índice único falharia — logamos para diagnóstico.
    dupes = select_all(<<~SQL).to_a
      SELECT tenant_id, phone_number_id, COUNT(*) AS n
        FROM whatsapp_sender_numbers
       GROUP BY tenant_id, phone_number_id
      HAVING COUNT(*) > 1
    SQL
    if dupes.any?
      say "AVISO: colisão (tenant_id, phone_number_id) em whatsapp_sender_numbers: #{dupes.inspect}", true
    end

    if index_exists?(:whatsapp_sender_numbers, :phone_number_id, name: :index_whatsapp_sender_numbers_on_phone_number_id)
      remove_index :whatsapp_sender_numbers, name: :index_whatsapp_sender_numbers_on_phone_number_id
    end

    unless index_exists?(:whatsapp_sender_numbers, [:tenant_id, :phone_number_id], name: :idx_wa_sender_numbers_on_tenant_and_phone_number)
      add_index :whatsapp_sender_numbers, [:tenant_id, :phone_number_id], unique: true,
                name: :idx_wa_sender_numbers_on_tenant_and_phone_number
    end
  end

  def down
    if index_exists?(:whatsapp_sender_numbers, [:tenant_id, :phone_number_id], name: :idx_wa_sender_numbers_on_tenant_and_phone_number)
      remove_index :whatsapp_sender_numbers, name: :idx_wa_sender_numbers_on_tenant_and_phone_number
    end
    unless index_exists?(:whatsapp_sender_numbers, :phone_number_id, name: :index_whatsapp_sender_numbers_on_phone_number_id)
      add_index :whatsapp_sender_numbers, :phone_number_id, unique: true,
                name: :index_whatsapp_sender_numbers_on_phone_number_id
    end
  end
end
