class AddIntakeReviewPolicySnapshotToHabitations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_column_if_allowed :habitations, :intake_review_policy_version, :integer
    add_column_if_allowed :habitations, :intake_review_policy_snapshot, :jsonb, default: {}, null: false

    add_index_if_allowed :habitations,
                         [:tenant_id, :intake_status, :intake_review_policy_version],
                         name: "index_habitations_on_tenant_intake_policy_version",
                         if_not_exists: true
  end

  private

  def add_column_if_allowed(table, column, type, **options)
    return if column_exists?(table, column)

    add_column table, column, type, **options
  rescue ActiveRecord::StatementInvalid => error
    raise unless insufficient_privilege?(error)

    say "Skipping #{table}.#{column}: database user is not table owner", true
  end

  def add_index_if_allowed(table, columns, **options)
    return unless columns.all? { |column| column_exists?(table, column) }

    add_index table, columns, **options
  rescue ActiveRecord::StatementInvalid => error
    raise unless insufficient_privilege?(error)

    say "Skipping index #{options[:name]}: database user is not table owner", true
  end

  def insufficient_privilege?(error)
    error.cause.is_a?(PG::InsufficientPrivilege) || error.message.include?("must be owner")
  end
end
