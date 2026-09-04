# Rails dumps/loads db/structure.sql with PostgreSQL client tools. In local
# development this app may have multiple Homebrew versions installed; prefer
# the newest client tools, then remove pg_dump output that PG16 servers cannot
# load.
if Rails.env.development? || Rails.env.test?
  postgresql_client_bin_paths = [
    ENV["POSTGRESQL_CLIENT_BIN"],
    "/opt/homebrew/opt/postgresql@17/bin",
    "/usr/local/opt/postgresql@17/bin"
  ].compact_blank

  selected_postgresql_client_bin = postgresql_client_bin_paths.find do |path|
    File.executable?(File.join(path, "pg_dump")) && File.executable?(File.join(path, "psql"))
  end

  if selected_postgresql_client_bin.present?
    current_path_entries = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)

    unless current_path_entries.first == selected_postgresql_client_bin
      ENV["PATH"] = ([selected_postgresql_client_bin] + current_path_entries.reject { |entry| entry == selected_postgresql_client_bin }).join(File::PATH_SEPARATOR)
    end
  end

  ActiveSupport.on_load(:active_record) do
    require "active_record/tasks/postgresql_database_tasks"

    module PostgreSQLStructureCompatibility
      INCOMPATIBLE_WITH_PG16 = /\ASET transaction_timeout = 0;\s*\z/

      def structure_dump(filename, extra_flags)
        super.tap { sanitize_structure_dump(filename) }
      end

      private

      def sanitize_structure_dump(filename)
        return unless File.exist?(filename)

        lines = File.readlines(filename)
        sanitized = lines.reject { |line| line.match?(INCOMPATIBLE_WITH_PG16) }
        return if sanitized.length == lines.length

        File.write(filename, sanitized.join)
      end
    end

    ActiveRecord::Tasks::PostgreSQLDatabaseTasks.prepend(PostgreSQLStructureCompatibility)
  end
end
