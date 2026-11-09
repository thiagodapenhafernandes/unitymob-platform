module Instagram
  # Referência assinada e escopada por conta; nunca expõe dados do contato no site.
  class PropertyJourney
    COOKIE_KEY = 'unitymob_instagram_reference'.freeze
    PURPOSE = 'instagram_site'.freeze

    def self.reference(lead)
      return if lead.instagram_scoped_id.blank?
      lead.signed_id(purpose: PURPOSE, expires_in: 30.days)
    end

    def self.resolve(tenant, token)
      return unless token.is_a?(String) && token.present? && token.bytesize <= 1000
      lead = tenant.leads.find_signed(token, purpose: PURPOSE)
      lead if lead&.tenant_id == tenant.id && lead.instagram_scoped_id.present? && lead.archived_at.blank?
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    def self.token_from_url(url)
      Rack::Utils.parse_query(URI.parse(url.to_s).query.to_s)['ig_ref']
    rescue URI::InvalidURIError, ArgumentError
      nil
    end

    def self.properties_in(tenant, text)
      urls = text.to_s.scan(%r{https?://[^\s<>]+})
      return [] if urls.empty?
      base = URI.parse(tenant.public_base_url.to_s)
      refs = urls.filter_map do |url|
        uri = URI.parse(url.sub(/[.,;!]+\z/, ''))
        URI.decode_www_form_component(uri.path.delete_prefix('/imoveis/')) if uri.host.to_s.downcase.delete_prefix("www.") == base.host.to_s.downcase.delete_prefix("www.") && uri.path.start_with?('/imoveis/')
      rescue URI::InvalidURIError, ArgumentError
        nil
      end
      scope = tenant.habitations.public_property_listable
      properties = scope.where(slug: refs).or(scope.where(codigo: refs)).to_a
      refs.filter_map { |ref| properties.find { |property| property.slug == ref || property.codigo == ref } }.uniq
    end

    def self.track_links(lead, text)
      return text if lead.instagram_scoped_id.blank?
      properties = properties_in(lead.tenant, text)
      return text if properties.empty?
      token = reference(lead)
      host = URI.parse(lead.tenant.public_base_url).host.to_s.downcase.delete_prefix('www.')
      refs = properties.flat_map { |property| [property.slug, property.codigo] }.compact
      text.gsub(%r{https?://[^\s<>]+}) do |url|
        clean = url.sub(/[.,;!]+\z/, '')
        suffix = url.delete_prefix(clean)
        uri = URI.parse(clean)
        ref = URI.decode_www_form_component(uri.path.delete_prefix('/imoveis/'))
        next url unless uri.host.to_s.downcase.delete_prefix('www.') == host && uri.path.start_with?('/imoveis/') && refs.include?(ref)
        uri.query = Rack::Utils.parse_query(uri.query.to_s).merge('ig_ref' => token).to_query
        uri.to_s + suffix
      rescue URI::InvalidURIError, ArgumentError
        url
      end
    end

    def self.record!(lead, property, event, message_id: nil)
      return unless lead && property && property.tenant_id == lead.tenant_id
      lead.with_lock do
        metadata = { 'event' => event, 'habitation_id' => property.id, 'property_code' => property.codigo,
          'source' => 'instagram_direct', 'instagram_message_id' => message_id }.compact
        key = lead.activities.where(kind: 'instagram_property_event')
          .where("metadata ->> 'event' = ? AND metadata ->> 'habitation_id' = ?", event, property.id.to_s)
        key = key.where("metadata ->> 'instagram_message_id' = ?", message_id.to_s) if message_id
        key.first || lead.activities.create!(kind: 'instagram_property_event', source_category: 'automation', metadata: metadata)
      end
    end

    def self.record_message(message)
      lead = message.lead
      if message.outbound?
        properties_in(lead.tenant, message.body).each { |property| record!(lead, property, 'sent', message_id: message.id) }
        return
      end
      return if message.body.to_s.match?(/\b(?:n[aã]o (?:tenho interesse|gostei|quero)|sem interesse|outr[oa]s? op[cç][oõ]es|mais op[cç][oõ]es)\b/i)
      return unless message.body.to_s.match?(/\b(?:interess\w*|quero|gostei|pagamento|financiamento|visitar|saber mais)\b/i)
      explicit = properties_in(lead.tenant, message.body)
      choices = []
      lead.instagram_messages.outbound.where('id < ?', message.id).order(id: :desc).limit(10).detect do |reply|
        choices = properties_in(lead.tenant, reply.body)
        choices.any?
      end
      return if choices.empty? && explicit.empty?
      explicit = choices.select { |property| message.body.match?(/(?<![\p{L}\d])#{Regexp.escape(property.codigo.to_s)}(?![\p{L}\d])/i) } if explicit.empty?
      ordinal = message.body[/\b(primeir[oa]|segund[oa]|terceir[oa])\b/i]&.downcase
      index = { 'primeiro' => 0, 'primeira' => 0, 'segundo' => 1, 'segunda' => 1, 'terceiro' => 2, 'terceira' => 2 }[ordinal]
      selected = explicit.presence || (index ? [choices[index]].compact : (choices.size == 1 ? choices : []))
      selected.each do |property|
        lead.property_interests.find_or_create_by!(tenant: lead.tenant, habitation: property)
        record!(lead, property, 'interest', message_id: message.id)
      end
    end

    def self.receive!(inquiry, token:, distribution_rule: nil)
      target = resolve(inquiry.tenant, token)
      return Leads::Intake.receive!(inquiry, distribution_rule: distribution_rule) unless target
      raise ActiveRecord::RecordInvalid, inquiry unless inquiry.valid?

      reused = false
      result = inquiry.tenant.with_lock do
        existing = Leads::Intake.find_existing(inquiry)
        target.with_lock do
          if target.archived_at.blank? && !conflicting_identity?(target, inquiry) && (existing.nil? || existing.id == target.id)
            pending = target.instagram_capture_pending?
            target.skip_automatic_routing = true
            captured_name = CaptureAnswer.new(inquiry.name).name
            if captured_name && (target.client_name.blank? || CaptureAnswer.new(target.client_name).name.nil?)
              target.client_name = captured_name
            end
            target.name = target.client_name if target.name.blank? || target.name == ProfileEnrichmentJob::DEFAULT_NAME || target.name.start_with?('@')
            target.property_id ||= inquiry.property_id
            target.phone = inquiry.phone if target.display_phone.blank?
            target.email = inquiry.email if target.display_email.blank?
            Leads::InquiryComplement.complement!(target, inquiry, notify: false)
            target.attribution_data = target.attribution_data.to_h.merge('instagram_site_conversion' => true)
            if pending
              target.other_information = target.other_information.deep_merge('instagram_capture' => {
                'step' => 'completed', 'sdr_cursor' => target.instagram_messages.inbound.maximum(:id)
              })
            end
            target.save!
            target.intake_reused = true
            reused = true
            if pending
              distribution_rule ? Leads::DistributorService.distribute_to(target, distribution_rule) : Leads::RoutingService.route!(target)
            end
            target
          end
        end
      end
      result = Leads::Intake.receive!(inquiry, distribution_rule: distribution_rule) unless reused
      if property = inquiry.tenant.habitations.public_property_listable.find_by(id: inquiry.property_id)
        result.property_interests.find_or_create_by!(tenant: inquiry.tenant, habitation: property)
        record!(result, property, 'converted')
      end
      result
    end

    def self.conflicting_identity?(target, inquiry)
      phones = Leads::ContactMatch.phone_variants_for(target)
      emails = Leads::ContactMatch.email_variants_for(target)
      (phones.any? && (phones & Leads::ContactMatch.phone_variants_for(inquiry)).empty?) ||
        (emails.any? && Leads::ContactMatch.email_variants_for(inquiry).any? && (emails & Leads::ContactMatch.email_variants_for(inquiry)).empty?)
    end
  end
end
