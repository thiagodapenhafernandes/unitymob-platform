module Lovers
  class LeadSync
    MAX_PAGES = 50

    Result = Struct.new(:created, :updated, :invalid, :pages, :errors, keyword_init: true) do
      def total
        created.to_i + updated.to_i
      end

      def message
        "#{total} leads sincronizados (#{created} novos, #{updated} atualizados, #{invalid} inválidos)."
      end
    end

    class << self
      def call(setting:)
        new(setting:).call
      end
    end

    def initialize(setting:)
      @setting = setting
      @client = Lovers::Client.new(token: setting.stored_api_token)
    end

    def call
      counts = { created: 0, updated: 0, invalid: 0, pages: 0, errors: [] }
      page = 1

      loop do
        response = client.leads(page:, start_date: setting.sync_start_on, end_date: Date.current)
        items = Array(response["Data"])
        counts[:pages] += 1

        items.each do |payload|
          result = Lovers::LeadImporter.call(tenant: setting.tenant, payload:, origin: setting.default_origin)
          if result.success?
            counts[result.status] += 1
          else
            counts[:invalid] += 1
            counts[:errors] << result.errors.join(", ")
          end
        end

        break if items.empty? || response.dig("Links", "Next").blank? || page >= MAX_PAGES

        page += 1
      end

      Result.new(**counts)
    end

    private

    attr_reader :setting, :client
  end
end
