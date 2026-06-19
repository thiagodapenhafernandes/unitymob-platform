module RentalGuaranteeParamNormalizer
  extend ActiveSupport::Concern

  private

  def normalize_rental_guarantee_method_param!(key = :habitation)
    payload = params[key]
    return unless payload.respond_to?(:key?) && payload.key?(:rental_guarantee_method)

    payload[:rental_guarantee_method] = Array(payload[:rental_guarantee_method])
      .flatten
      .flat_map { |value| value.to_s.split(",") }
      .map(&:strip)
      .compact_blank
      .uniq
  end
end
