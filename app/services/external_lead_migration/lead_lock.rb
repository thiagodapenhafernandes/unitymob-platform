module ExternalLeadMigration
  module LeadLock
    NAMESPACE = 72420

    def self.synchronize(lead_id)
      Lead.connection_pool.with_connection do |connection|
        acquired = connection.select_value("SELECT pg_try_advisory_lock(#{NAMESPACE}, #{Integer(lead_id)})")
        return false unless acquired

        begin
          yield
          true
        ensure
          connection.select_value("SELECT pg_advisory_unlock(#{NAMESPACE}, #{Integer(lead_id)})")
        end
      end
    end
  end
end
