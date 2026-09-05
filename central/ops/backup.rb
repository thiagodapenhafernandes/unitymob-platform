# Run from central/ with production environment, via the systemd backup service.
require 'aws-sdk-s3'
require 'tempfile'
require 'time'

Tempfile.create(['unitymob-central-', '.dump']) do |dump|
  env = { 'PGPASSWORD' => ENV.fetch('DB_PASSWORD') }
  pid = Process.spawn(env, 'pg_dump', '--format=custom', '--no-owner', '--no-acl',
    '--host', ENV.fetch('DB_HOST'), '--port', ENV.fetch('DB_PORT', '5432'),
    '--username', ENV.fetch('DB_USERNAME'), '--file', dump.path, ENV.fetch('CENTRAL_DB_NAME'))
  Process.wait(pid)
  abort 'Database backup failed' unless $?.success? && File.size(dump.path).positive?
  s3 = Aws::S3::Resource.new(access_key_id: ENV.fetch('SUPPORT_STORAGE_KEY'),
    secret_access_key: ENV.fetch('SUPPORT_STORAGE_SECRET'), region: ENV.fetch('SUPPORT_STORAGE_REGION'),
    endpoint: ENV.fetch('SUPPORT_STORAGE_ENDPOINT'))
  key = "database-backups/#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.dump"
  object = s3.bucket(ENV.fetch('SUPPORT_STORAGE_BUCKET')).object(key)
  object.upload_file(dump.path, acl: 'private')
  abort 'Backup size mismatch' unless object.content_length == File.size(dump.path)
  puts "Database backup uploaded: #{key} (#{File.size(dump.path)} bytes)"
end
