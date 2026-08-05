class StopStorageEnvLeakToNonDefaultTenants < ActiveRecord::Migration[7.1]
  def up
    default_slug = ENV.fetch("DEFAULT_TENANT_SLUG", "default")
    do_bucket = ENV["DO_SPACES_BUCKET"].to_s.presence
    s3_buckets = [ENV["AWS_S3_BUCKET"].to_s.presence, ENV["S3_BUCKET"].to_s.presence].compact.uniq

    conditions = []
    conditions << sanitize_sql_array(["storage_integration_settings.do_spaces_bucket = ?", do_bucket]) if do_bucket
    s3_buckets.each do |bucket|
      conditions << sanitize_sql_array(["storage_integration_settings.s3_bucket = ?", bucket])
    end
    return if conditions.blank?

    execute <<~SQL.squish
      UPDATE storage_integration_settings
      SET
        photo_provider = 'local',
        document_provider = 'local',
        do_spaces_bucket = NULL,
        do_spaces_public_base_url = NULL,
        do_spaces_access_key_id_ciphertext = NULL,
        do_spaces_secret_access_key_ciphertext = NULL,
        s3_bucket = NULL,
        s3_endpoint = NULL,
        s3_public_base_url = NULL,
        s3_access_key_id_ciphertext = NULL,
        s3_secret_access_key_ciphertext = NULL,
        updated_at = CURRENT_TIMESTAMP
      FROM tenants
      WHERE tenants.id = storage_integration_settings.tenant_id
        AND tenants.slug <> #{connection.quote(default_slug)}
        AND (#{conditions.join(" OR ")})
    SQL
  end

  def down
    # Dados de credenciais removidos de tenants não-default não são reconstruíveis com segurança.
  end

  private

  def sanitize_sql_array(array)
    ActiveRecord::Base.send(:sanitize_sql_array, array)
  end
end
