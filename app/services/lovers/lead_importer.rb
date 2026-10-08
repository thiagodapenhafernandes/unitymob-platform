module Lovers
  class LeadImporter
    Result = Struct.new(:lead, :status, :errors, keyword_init: true) do
      def success?
        lead&.persisted? && errors.blank?
      end
    end

    class << self
      def call(tenant:, payload:, origin: LoversIntegrationSetting::DEFAULT_ORIGIN)
        new(tenant:, payload:, origin:).call
      end
    end

    def initialize(tenant:, payload:, origin:)
      @tenant = tenant
      @payload = normalize_hash(payload)
      @origin = origin.to_s.presence || LoversIntegrationSetting::DEFAULT_ORIGIN
    end

    def call
      lead = tenant.leads.new
      lead.assign_attributes(lead_attributes)
      begin
        lead = Leads::Intake.receive!(lead)
      rescue ActiveRecord::RecordInvalid => error
        lead = error.record
      end
      Result.new(lead:, status: lead.intake_reused ? :updated : :created, errors: lead.errors.full_messages)
    end

    private

    attr_reader :tenant, :payload, :origin

    def lead_attributes
      {
        tenant:,
        name: field_value("Name") || field_value("Email") || "Lead Lovers",
        email: field_value("Email"),
        phone: Phones::Normalizer.call(field_value("Phone")),
        lead_type: "lovers",
        origin:,
        product: field_value("Company", "Source", "Src"),
        other_information: {
          "lovers_payload" => payload,
          "lovers_code" => field_value("Code", "Id"),
          "lovers_score" => field_value("Score"),
          "lovers_status" => field_value("Status"),
          "lovers_source" => field_value("Source", "Src"),
          "lovers_city" => field_value("City"),
          "lovers_state" => field_value("State"),
          "lovers_registration_date" => field_value("RegistrationDate"),
          "lovers_imported_at" => Time.current.iso8601
        }.compact
      }.compact
    end

    def field_value(*keys)
      keys.each do |key|
        value = payload[key] || payload[key.to_sym]
        return value.to_s.strip if value.present?
      end
      nil
    end

    def normalize_hash(value)
      if value.respond_to?(:to_unsafe_h)
        value.to_unsafe_h
      elsif value.respond_to?(:to_h)
        value.to_h
      else
        {}
      end
    end
  end
end
