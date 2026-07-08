class CreateErrorEvents < ActiveRecord::Migration[7.1]
  # Rastreador interno de erros (substituto caseiro do Sentry). Uma linha por
  # fingerprint (classe + mensagem normalizada + top frames do app); ocorrências
  # repetidas só incrementam o contador.
  def change
    create_table :error_events do |t|
      t.string  :fingerprint, null: false
      t.string  :exception_class
      t.text    :message
      t.text    :backtrace
      t.string  :source # request | job | manual
      t.string  :severity, default: "error", null: false
      # Sem FK de propósito: o erro precisa ser gravável mesmo com o tenant
      # deletado/quebrado (e por isso também não entra no HardDeleter).
      t.bigint  :tenant_id
      t.jsonb   :context, default: {}, null: false
      t.integer :occurrences_count, default: 1, null: false
      t.datetime :first_seen_at
      t.datetime :last_seen_at
      t.datetime :last_alerted_at
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :error_events, :fingerprint, unique: true
    add_index :error_events, :last_seen_at
    add_index :error_events, [:tenant_id, :last_seen_at]
  end
end
