module Leads
  # Local do interesse comercial da consulta atual, nunca endereço/IP da pessoa.
  class EntryLocation
    def self.city(entry)
      property = entry.tenant.habitations.find_by(id: entry.property_id) if entry.property_id.present?
      return property.cidade.presence if property

      info = entry.other_information.to_h
      attribution = entry.attribution_data.to_h
      explicit = info["property_city"].presence || info["interest_city"].presence
      if explicit.blank? && entry.respond_to?(:answer_for)
        explicit = entry.answer_for("property_city").presence || entry.answer_for("interest_city").presence
      end
      return explicit if explicit.is_a?(String)

      payload = info["external_lead_payload"]
      attributes = payload["attributes"] if payload.is_a?(Hash)
      products = [attribution["product"], info["external_lead_product"],
        (attributes["product"] if attributes.is_a?(Hash))]
      products.filter_map { |product| product["city"].presence if product.is_a?(Hash) }.find { |city| city.is_a?(String) }
    end

    def self.normalized_city(value)
      I18n.transliterate(value.to_s).squish.downcase
    end
  end
end
