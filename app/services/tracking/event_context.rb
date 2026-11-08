module Tracking
  class EventContext
    def self.property(property, business_type: nil)
      return {} unless property

      type = business_type.presence || Leads::Attribution.business_type(property.whatsapp_negotiation_type)
      cents = case type
      when 'venda' then property.valor_venda_cents
      when 'locacao', 'diaria' then property.valor_locacao_cents
      end
      address = property.address
      {
        property_id: property.id.to_s, property_code: property.codigo, property_name: property.display_title,
        property_type: property.categoria&.parameterize(separator: '_'),
        property_price: cents&.positive? ? cents.to_f / 100 : nil,
        property_bedrooms: property.dormitorios_qtd, property_suites: property.suites_qtd,
        property_parking: property.vagas_qtd, property_area_m2: property.area_privativa_m2&.to_f,
        property_neighborhood: address&.bairro, property_city: address&.cidade, property_state: address&.uf
      }.compact_blank
    end

    def self.ecommerce(context, business_type:)
      return if context[:property_code].blank?

      { items: [{ item_id: context[:property_code], item_name: context[:property_name], item_category: context[:property_type],
        item_category2: business_type, item_category3: context[:property_city],
        item_category4: context[:property_neighborhood], price: context[:property_price], quantity: 1 }.compact_blank] }
    end

    def self.user_data(identity, external_id:)
      email = (identity['email'].presence || identity['client_email']).to_s.downcase.gsub(/\s/, '')
      phone_value = identity['phone'].presence || identity['client_phone']
      normalized_phone = Phones::Normalizer.call(phone_value)
      phone = Phones::PublicWhatsapp.new(normalized_phone.present? ? "+#{normalized_phone}" : phone_value)
      name = (identity['name'].presence || identity['client_name']).to_s
      first, last = I18n.transliterate(name).downcase.gsub(/[^a-z\s]/, '').squish.split(' ', 2)
      { email_address: email.match?(URI::MailTo::EMAIL_REGEXP) ? email : nil,
        phone_number: phone.error ? nil : phone.e164, external_id: external_id.to_s,
        address: { first_name: first, last_name: last }.compact_blank.presence }.compact_blank
    end

    def self.lead_channel(lead)
      return 'meta_lead_ads' if lead.other_information.to_h['meta_leadgen_id'].present?
      return 'site_modal' if lead.lead_type == 'whatsapp_modal'
      return 'portal' if lead.attribution_channel == 'portal'
      return 'whatsapp_direto' if lead.whatsapp_service_contact? || lead.origin.to_s.downcase.include?('whatsapp')
      return 'indicacao' if I18n.transliterate(lead.origin.to_s).downcase.include?('indicacao')

      'outro'
    end

    def self.offline(lead, event:, identity:, occurred_at:, business_type:)
      attribution = lead.attribution_data.to_h
      property = lead.tenant.habitations.find_by(id: lead.property_id) if lead.property_id
      visitor = if attribution['analytics_consent'] == 'granted'
        attribution.slice('fbc', 'fbp', 'gclid', 'gbraid', 'wbraid').symbolize_keys.merge(
          ip: attribution['client_ip_address'], user_agent: attribution['client_user_agent'],
          landing_url: page_url(attribution['landing_url'])).compact_blank
      end
      stage = { 'qualify_lead'=>'qualificado', 'visit'=>'visita_realizada', 'proposal'=>'proposta_enviada', 'closed'=>'fechado' }.fetch(event)
      {
        business_type: Leads::Attribution.business_type(business_type == 'aluguel' ? 'rent' : business_type),
        conversion_datetime: occurred_at.in_time_zone('America/Sao_Paulo').iso8601,
        lead_stage: stage, lead_channel: lead_channel(lead),
        user_data: user_data(identity, external_id: lead.id),
        meta_lead_id: lead.other_information.to_h['meta_leadgen_id'].presence,
        visitor: visitor.presence
      }.compact.merge(self.property(property, business_type: Leads::Attribution.business_type(business_type == 'aluguel' ? 'rent' : business_type)))
        .merge(attribution.slice('utm_source','utm_medium','utm_campaign','utm_term').symbolize_keys.compact_blank)
    end

    def self.page_url(value)
      uri = URI.parse(value.to_s)
      return unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?

      uri.query = uri.fragment = nil
      uri.to_s
    rescue URI::InvalidURIError
      nil
    end
  end
end
