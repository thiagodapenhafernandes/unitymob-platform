module Ai
  module PropertySearch
    class DataSource
      class UnsupportedSource < StandardError; end

      ADAPTERS = {
        "database" => DatabaseQuery
      }.freeze

      def self.call(tenant:, admin_user:, setting:, filters:, sort: nil, allow_flexible: true)
        adapter = ADAPTERS[setting.ai_property_search_data_source]
        unless adapter
          raise UnsupportedSource, "A fonte #{setting.ai_property_search_data_source} ainda não possui um adaptador autorizado configurado."
        end

        adapter.new(tenant:, admin_user:, setting:, filters:, sort:, allow_flexible:).call
      end
    end
  end
end
