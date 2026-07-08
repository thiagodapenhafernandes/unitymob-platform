class AddUniqueWaMessageIdIndexToWhatsappMessages < ActiveRecord::Migration[7.1]
  # Fecha a corrida do dedupe de webhook no Whatsapp::InboundProcessor
  # (exists? + create! não atômico): unique parcial por tenant, o mesmo escopo
  # da query de dedupe (tenant.whatsapp_messages.exists?(wa_message_id:)).
  # Parcial porque mensagens outbound pendentes ficam com wa_message_id NULL.
  # O índice global não-único em wa_message_id permanece — atende os lookups
  # sem tenant (resolução de tenant por status em inbound_processor.rb).
  INDEX_NAME = "index_whatsapp_messages_on_tenant_id_and_wa_message_id".freeze

  def up
    # Neutraliza duplicatas existentes antes do unique: mantém a mensagem mais
    # antiga por (tenant_id, wa_message_id) e anula o wamid das mais novas.
    # UPDATE idempotente: re-execução não encontra rn > 1.
    affected = execute(<<~SQL).cmd_tuples
      WITH ranked AS (
        SELECT id,
               row_number() OVER (
                 PARTITION BY tenant_id, wa_message_id
                 ORDER BY created_at ASC, id ASC
               ) AS rn
        FROM whatsapp_messages
        WHERE wa_message_id IS NOT NULL
      )
      UPDATE whatsapp_messages
      SET wa_message_id = NULL
      FROM ranked
      WHERE whatsapp_messages.id = ranked.id
        AND ranked.rn > 1
    SQL
    say "Mensagens duplicadas de wa_message_id neutralizadas: #{affected}"

    unless index_exists?(:whatsapp_messages, [:tenant_id, :wa_message_id], name: INDEX_NAME)
      add_index :whatsapp_messages, [:tenant_id, :wa_message_id],
                unique: true, where: "wa_message_id IS NOT NULL", name: INDEX_NAME
    end
  end

  def down
    if index_exists?(:whatsapp_messages, [:tenant_id, :wa_message_id], name: INDEX_NAME)
      remove_index :whatsapp_messages, name: INDEX_NAME
    end
    # A anulação dos wa_message_id duplicados não é revertida.
  end
end
