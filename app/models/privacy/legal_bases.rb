module Privacy
  module LegalBases
    POLICY_VERSION = "2026-10-12".freeze

    OPTIONS = [
      ["Legítimo interesse", "legitimate_interest"],
      ["Consentimento", "consent"],
      ["Contrato preexistente", "pre_existent_contract"],
      ["Processo judicial", "judicial_process"],
      ["Interesse público", "public_interest"],
      ["Proteção da vida", "vital_interest"]
    ].freeze

    def self.data_processing(type = "legitimate_interest")
      [{ category: "data_processing", type: type, status: "granted" }]
    end

    def self.for_information(information)
      type = information.to_h.dig("unitymob_data_processing_policy", "legal_bases", 0, "type")
      data_processing(OPTIONS.map(&:last).include?(type) ? type : "legitimate_interest")
    end

    def self.record(type = "legitimate_interest", manual: false)
      {
        "legal_bases" => data_processing(type).as_json,
        "source" => manual ? "manual_registration" : "unitymob_policy_default",
        "policy_version" => POLICY_VERSION,
        "recorded_at" => Time.current.iso8601
      }
    end
  end
end
