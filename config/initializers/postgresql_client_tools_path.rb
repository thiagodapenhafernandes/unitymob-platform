# Rails dumps db/structure.sql with pg_dump after migrations. In local
# development this app runs against PostgreSQL 17, but Homebrew may expose an
# older pg_dump first in PATH. Keep the client tools aligned with the server.
if Rails.env.development? || Rails.env.test?
  postgresql_client_bin_paths = [
    ENV["POSTGRESQL_CLIENT_BIN"],
    "/opt/homebrew/opt/postgresql@17/bin",
    "/usr/local/opt/postgresql@17/bin"
  ].compact_blank

  selected_postgresql_client_bin = postgresql_client_bin_paths.find do |path|
    File.executable?(File.join(path, "pg_dump"))
  end

  if selected_postgresql_client_bin.present?
    current_path_entries = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)

    unless current_path_entries.first == selected_postgresql_client_bin
      ENV["PATH"] = ([selected_postgresql_client_bin] + current_path_entries.reject { |entry| entry == selected_postgresql_client_bin }).join(File::PATH_SEPARATOR)
    end
  end
end
