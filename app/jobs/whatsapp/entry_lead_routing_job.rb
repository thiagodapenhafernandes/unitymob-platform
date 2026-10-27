module Whatsapp
  class EntryLeadRoutingJob < ApplicationJob
    queue_as :sync

    def perform(tenant_id, lead_id, message_id)
      tenant = Tenant.find_by(id: tenant_id)
      lead = tenant&.leads&.find_by(id: lead_id)
      message = tenant&.whatsapp_messages&.inbound&.find_by(id: message_id)
      return unless lead && message && message.whatsapp_conversation.lead_id == lead.id

      Current.set(tenant: tenant) do
        lead.with_lock do
          info = lead.other_information.to_h
          entry = info.fetch("whatsapp_entry", {})
          return unless lead.whatsapp_service_contact? && lead.admin_user_id.nil? && lead.distribution_rule_id.nil? && lead.archived_at.nil?
          return unless entry["message_id"] == message.wa_message_id

          distributor = Leads::DistributorService.new(lead)
          rule = distributor.matching_entry_rule(message: message)
          return unless rule

          lead.skip_automatic_routing = true
          lead.promote_whatsapp_contact!
          distributor.distribute_to(rule)
        end
      end
    end
  end
end
