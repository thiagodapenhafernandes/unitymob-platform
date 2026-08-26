# frozen_string_literal: true

module Gateway
  module AccountResolver
    module_function

    def call(email:)
      normalized = email.to_s.strip.downcase
      return if normalized.empty?

      AccountRoute.find_by(email: normalized, active: true)
    end
  end
end
