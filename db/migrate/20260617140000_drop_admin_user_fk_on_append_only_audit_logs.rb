# Tabelas de auditoria append-only (trigger BEFORE UPDATE OR DELETE) não podem ter o
# admin_user_id nem nulificado nem deletado. Para permitir hard-delete de admin com
# reatribuição, removemos a FK bloqueante e mantemos o id como dado histórico imutável.
class DropAdminUserFkOnAppendOnlyAuditLogs < ActiveRecord::Migration[7.1]
  def up
    remove_foreign_key :data_export_audit_logs, column: :admin_user_id, if_exists: true
    remove_foreign_key :checkin_audit_logs, column: :admin_user_id, if_exists: true
    remove_foreign_key :checkin_audit_logs, column: :actor_admin_user_id, if_exists: true
  end

  def down
    add_foreign_key :data_export_audit_logs, :admin_users, column: :admin_user_id
    add_foreign_key :checkin_audit_logs, :admin_users, column: :admin_user_id
    add_foreign_key :checkin_audit_logs, :admin_users, column: :actor_admin_user_id
  end
end
