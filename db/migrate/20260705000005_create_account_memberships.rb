class CreateAccountMemberships < ActiveRecord::Migration[7.1]
  # Multi-conta por convite (modelo agência/RD Station): a conta convida um
  # e-mail; no aceite nasce (ou reativa) um admin_user ESPELHO no tenant
  # convidado, linkado ao usuário primário. O convite carrega o snapshot de
  # acesso escolhido por quem convidou (perfil/gestores/área).
  def up
    unless table_exists?(:account_memberships)
      create_table :account_memberships do |t|
        t.references :tenant, null: false, foreign_key: true
        t.string :invited_email, null: false
        t.references :primary_admin_user, foreign_key: { to_table: :admin_users }
        t.references :member_admin_user, foreign_key: { to_table: :admin_users }, index: { unique: true }

        # Snapshot de acesso escolhido no convite
        t.references :profile, null: false, foreign_key: true
        t.references :horizontal_profile, foreign_key: { to_table: :profiles }
        t.references :manager, foreign_key: { to_table: :admin_users }
        t.references :rentals_manager, foreign_key: { to_table: :admin_users }
        t.integer :acting_type

        t.integer :status, null: false, default: 0 # invited/active/revoked
        t.references :invited_by, null: false, foreign_key: { to_table: :admin_users }
        t.string :invite_token_digest
        t.datetime :invite_sent_at
        t.datetime :invite_expires_at
        t.datetime :accepted_at
        t.datetime :revoked_at
        t.references :revoked_by, foreign_key: { to_table: :admin_users }

        t.timestamps
      end
    end

    unless index_exists?(:account_memberships, :invite_token_digest, name: :idx_account_memberships_on_token_digest)
      add_index :account_memberships, :invite_token_digest, unique: true, name: :idx_account_memberships_on_token_digest
    end

    # Um convite vivo por e-mail por conta (revogados liberam reconvite).
    execute <<~SQL
      CREATE UNIQUE INDEX IF NOT EXISTS idx_account_memberships_live_email
      ON account_memberships (tenant_id, lower(invited_email))
      WHERE status <> 2
    SQL
  end

  def down
    drop_table :account_memberships if table_exists?(:account_memberships)
  end
end
