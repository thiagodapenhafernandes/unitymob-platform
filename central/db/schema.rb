# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_09_05_210000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "sla_policies", force: :cascade do |t|
    t.string "priority", null: false
    t.integer "first_response_minutes"
    t.integer "resolution_minutes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["priority"], name: "index_sla_policies_on_priority", unique: true
  end

  create_table "sla_policy_changes", force: :cascade do |t|
    t.bigint "staff_id", null: false
    t.string "priority", null: false
    t.jsonb "changeset", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.index ["staff_id"], name: "index_sla_policy_changes_on_staff_id"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "staff_presence_windows", force: :cascade do |t|
    t.bigint "staff_session_id", null: false
    t.datetime "started_at", null: false
    t.datetime "confirmed_until", null: false
    t.index ["staff_session_id"], name: "index_staff_presence_windows_on_staff_session_id"
  end

  create_table "staff_sessions", force: :cascade do |t|
    t.bigint "staff_id", null: false
    t.string "role", null: false
    t.datetime "started_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_seen_at"
    t.datetime "last_activity_at"
    t.datetime "ended_at"
    t.string "end_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ended_at", "expires_at"], name: "index_staff_sessions_on_ended_at_and_expires_at"
    t.index ["staff_id"], name: "index_staff_sessions_on_staff_id"
  end

  create_table "staffs", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "role", null: false
    t.string "password_digest"
    t.text "otp_secret"
    t.bigint "otp_consumed_at"
    t.boolean "active", default: true, null: false
    t.integer "session_version", default: 0, null: false
    t.datetime "activated_at"
    t.string "activation_digest"
    t.datetime "activation_expires_at"
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "locked_until"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "verification_method", default: "totp", null: false
    t.string "email_code_digest"
    t.string "email_challenge_digest"
    t.datetime "email_code_expires_at"
    t.datetime "email_code_sent_at"
    t.integer "email_code_attempts", default: 0, null: false
    t.jsonb "queue_preferences", default: {}, null: false
    t.index "lower((email)::text)", name: "index_staffs_on_lower_email", unique: true
    t.index ["activation_digest"], name: "index_staffs_on_activation_digest", unique: true
  end

  create_table "support_access_sessions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "ticket_id", null: false
    t.string "token_digest", null: false
    t.string "operator_id", null: false
    t.string "operator_name", null: false
    t.string "requester_id", null: false
    t.datetime "redeem_before", null: false
    t.datetime "started_at"
    t.datetime "expires_at"
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_support_access_sessions_on_account_id"
    t.index ["ticket_id"], name: "index_support_access_sessions_on_ticket_id"
    t.index ["token_digest"], name: "index_support_access_sessions_on_token_digest", unique: true
  end

  create_table "support_accounts", force: :cascade do |t|
    t.string "uid", null: false
    t.string "name", null: false
    t.bigint "local_tenant_id"
    t.string "endpoint", null: false
    t.text "secret", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "control_revision", default: 0, null: false
    t.index ["local_tenant_id"], name: "index_support_accounts_on_local_tenant_id", unique: true
    t.index ["uid"], name: "index_support_accounts_on_uid", unique: true
  end

  create_table "support_audits", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "ticket_id"
    t.string "actor", null: false
    t.string "action", null: false
    t.jsonb "details", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_support_audits_on_account_id"
    t.index ["ticket_id"], name: "index_support_audits_on_ticket_id"
  end

  create_table "support_deliveries", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "ticket_id"
    t.string "uid", null: false
    t.jsonb "payload", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "delivered_at"
    t.datetime "next_attempt_at", null: false
    t.string "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "failed_at"
    t.index ["account_id"], name: "index_support_deliveries_on_account_id"
    t.index ["delivered_at", "next_attempt_at"], name: "index_support_deliveries_on_delivered_at_and_next_attempt_at"
    t.index ["ticket_id"], name: "index_support_deliveries_on_ticket_id"
    t.index ["uid"], name: "index_support_deliveries_on_uid", unique: true
  end

  create_table "support_labels", force: :cascade do |t|
    t.string "name", limit: 40, null: false
    t.string "color", default: "#64748b", null: false
    t.string "description", limit: 160
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_support_labels_on_lower_name", unique: true
  end

  create_table "support_messages", force: :cascade do |t|
    t.bigint "ticket_id", null: false
    t.string "uid", null: false
    t.string "side", null: false
    t.string "author", null: false
    t.text "body", default: "", null: false
    t.boolean "internal", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "notification_pending", default: false, null: false
    t.datetime "notified_at"
    t.bigint "author_staff_id"
    t.datetime "edited_at"
    t.datetime "deleted_at"
    t.integer "revision", default: 0, null: false
    t.index ["notification_pending"], name: "index_support_messages_on_notification_pending", where: "(notification_pending = true)"
    t.index ["ticket_id"], name: "index_support_messages_on_ticket_id"
    t.index ["uid"], name: "index_support_messages_on_uid", unique: true
  end

  create_table "support_notification_reads", force: :cascade do |t|
    t.bigint "staff_id", null: false
    t.bigint "ticket_id", null: false
    t.bigint "message_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["staff_id", "ticket_id"], name: "index_support_notification_reads_on_staff_id_and_ticket_id", unique: true
    t.index ["staff_id"], name: "index_support_notification_reads_on_staff_id"
    t.index ["ticket_id"], name: "index_support_notification_reads_on_ticket_id"
  end

  create_table "support_receipts", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "uid", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "uid"], name: "index_support_receipts_on_account_id_and_uid", unique: true
    t.index ["account_id"], name: "index_support_receipts_on_account_id"
  end

  create_table "support_ticket_events", force: :cascade do |t|
    t.bigint "ticket_id", null: false
    t.bigint "staff_id"
    t.string "kind", null: false
    t.string "status", null: false
    t.bigint "assignee_id"
    t.jsonb "details", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.index ["staff_id", "occurred_at"], name: "index_support_ticket_events_on_staff_id_and_occurred_at"
    t.index ["staff_id"], name: "index_support_ticket_events_on_staff_id"
    t.index ["ticket_id", "occurred_at", "id"], name: "idx_on_ticket_id_occurred_at_id_9ef7940907"
    t.index ["ticket_id"], name: "index_support_ticket_events_on_ticket_id"
  end

  create_table "support_tickets", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "uid", null: false
    t.string "requester_id", null: false
    t.string "requester_name", null: false
    t.string "subject", null: false
    t.jsonb "intake", default: {}, null: false
    t.string "source_path"
    t.string "status", default: "aberto", null: false
    t.string "priority", default: "normal", null: false
    t.bigint "assignee_id"
    t.string "assignee_name"
    t.string "labels", default: "", null: false
    t.string "previous_uid"
    t.integer "revision", default: 0, null: false
    t.datetime "first_response_at"
    t.datetime "resolved_at"
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "diagnostics", default: {}, null: false
    t.string "origin", default: "receptivo", null: false
    t.string "outreach_kind"
    t.string "requester_email"
    t.index ["account_id", "requester_id", "updated_at"], name: "idx_on_account_id_requester_id_updated_at_91392e48ef"
    t.index ["account_id"], name: "index_support_tickets_on_account_id"
    t.index ["assignee_id"], name: "index_support_tickets_on_assignee_id"
    t.index ["origin", "created_at"], name: "index_support_tickets_on_origin_and_created_at"
    t.index ["status", "updated_at"], name: "index_support_tickets_on_status_and_updated_at"
    t.index ["uid"], name: "index_support_tickets_on_uid", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "sla_policy_changes", "staffs"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "staff_presence_windows", "staff_sessions"
  add_foreign_key "staff_sessions", "staffs"
  add_foreign_key "support_access_sessions", "support_accounts", column: "account_id"
  add_foreign_key "support_access_sessions", "support_tickets", column: "ticket_id"
  add_foreign_key "support_audits", "support_accounts", column: "account_id"
  add_foreign_key "support_audits", "support_tickets", column: "ticket_id"
  add_foreign_key "support_deliveries", "support_accounts", column: "account_id"
  add_foreign_key "support_deliveries", "support_tickets", column: "ticket_id"
  add_foreign_key "support_messages", "support_tickets", column: "ticket_id"
  add_foreign_key "support_notification_reads", "staffs"
  add_foreign_key "support_notification_reads", "support_tickets", column: "ticket_id"
  add_foreign_key "support_receipts", "support_accounts", column: "account_id"
  add_foreign_key "support_ticket_events", "staffs"
  add_foreign_key "support_ticket_events", "staffs", column: "assignee_id"
  add_foreign_key "support_ticket_events", "support_tickets", column: "ticket_id"
  add_foreign_key "support_tickets", "staffs", column: "assignee_id"
  add_foreign_key "support_tickets", "support_accounts", column: "account_id"
end
