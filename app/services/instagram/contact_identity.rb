module Instagram
  class ContactIdentity
    # Só concilia uma identidade única e compatível com o match configurado pela conta.
    def self.resolve!(tenant:, page:, sender:, event:, source: nil)
      answer = CaptureAnswer.new(event.dig('message', 'text'))
      phone = answer.phone
      email = event.dig('message', 'text').to_s[/[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}/]
      return source unless phone || email
      inquiry = tenant.leads.new(client_phone: phone || source&.display_phone, client_email: email || source&.display_email)
      matches = Leads::Intake.matches(inquiry)
      return source unless matches
      candidates = matches.where(archived_at: nil).where.not(id: source&.id).limit(2).to_a
      return source if candidates.empty?
      target = candidates.one? ? candidates.first : nil
      compatible = target && !Lead.non_operational_status_values(tenant: tenant).include?(target.status) &&
        (target.instagram_scoped_id.blank? || target.instagram_account_id == page.instagram_id && target.instagram_scoped_id == sender)
      safe_source = !source || source.archived_at.nil? && source.admin_user_id.nil? && source.c2s_exported_at.nil? && source.origin == 'Instagram Direct' && !source.imported_from_c2s? && source.c2s_export_external_id.blank? &&
        %i[tasks appointments proposals whatsapp_conversations whatsapp_campaign_messages lead_labelings lead_favorites secure_links stage_automation_executions google_stage_conversion_events].none? { |name| source.public_send(name).exists? }
      unless compatible && safe_source
        source&.update_columns(other_information: source.other_information.to_h.merge('instagram_identity_conflict' => true))
        return source
      end
      tenant.with_lock do
        target.lock!
        source&.lock!
        return source if source&.admin_user_id.present? || target.instagram_scoped_id.present? &&
          (target.instagram_account_id != page.instagram_id || target.instagram_scoped_id != sender)
        if source
          source.update_columns(instagram_account_id: nil, instagram_scoped_id: nil)
          Leads::InquiryComplement.complement!(target, source, notify: false)
          source.property_interests.each { |i| target.property_interests.find_or_create_by!(tenant: tenant, habitation_id: i.habitation_id) }
          source.instagram_messages.update_all(lead_id: target.id)
          source.activities.update_all(lead_id: target.id)
          %i[public_navigation_sessions public_navigation_events client_property_interests automation_events seo_conversion_events push_delivery_events ai_property_share_collections].each do |association|
            source.public_send(association).update_all(lead_id: target.id)
          end
          InAppNotification.where(tenant_id: tenant.id).where("metadata ->> 'lead_id' = ?", source.id.to_s).update_all(read_at: Time.current)
        end
        attributes = {instagram_account_id: page.instagram_id, instagram_scoped_id: sender}
        attributes[:client_phone] = phone if target.display_phone.blank?
        attributes[:client_email] = email if target.display_email.blank?
        # Mantém dono, origem, status, modalidade e regras do cadastro canônico.
        target.update_columns(attributes)
        source&.destroy!
        LeadActivity.log!(lead: target, kind: 'note', metadata: {event: 'instagram_identity_linked', previous_lead_id: source&.id})
        target
      end
    end
  end
end
