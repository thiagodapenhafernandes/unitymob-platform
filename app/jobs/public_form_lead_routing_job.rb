class PublicFormLeadRoutingJob < ApplicationJob
  queue_as :default

  # Cria o Lead de uma submissão e distribui pela regra do formulário.
  # Idempotente: uma submissão gera no máximo um lead (lead_id + lock).
  # O roteamento automático é pulado para distribuir na regra escolhida;
  # atividade "received" e automação "lead_created" são refeitas aqui.
  def perform(submission_id)
    submission = PublicFormSubmission.find_by(id: submission_id)
    return if submission.nil?

    submission.with_lock do
      return if submission.lead_id.present?

      form = submission.public_form
      rule = form.distribution_rule
      instagram_target = Instagram::PropertyJourney.resolve(submission.tenant, submission.source["instagram_reference"])
      return if rule.nil? && instagram_target.nil?

      if submission.normalized_phone.blank?
        Rails.logger.warn("[PublicFormLeadRoutingJob] Submissão #{submission.id} sem telefone — lead não criado.")
        return
      end

      Current.set(tenant: submission.tenant) do
        lead = submission.tenant.leads.new(
          name: submission.normalized_name.presence || "Site — #{form.name}",
          email: submission.normalized_email,
          phone: submission.normalized_phone,
          origin: form.webhook_origin
        )
        lead.attribution_data = Leads::TrackingUid.merge({}, submission.source.slice("tracking_uid"))
        lead.skip_automatic_routing = true
        if instagram_target
          page_url = submission.source["page_url"]
          lead.property_id = Instagram::PropertyJourney.properties_in(submission.tenant, page_url).first&.id
          lead = Instagram::PropertyJourney.receive!(lead, token: submission.source["instagram_reference"], distribution_rule: rule)
        else
          lead = Leads::Intake.receive!(lead, distribution_rule: rule)
        end
        if lead.intake_reused
          submission.update!(lead_id: lead.id)
          return
        end
        lead.activities.create!(kind: "received", metadata: { origin: lead.origin })
        Leads::DistributorService.distribute_to(lead, rule)
        Automation::Dispatcher.dispatch(
          :lead_created, lead, source: "lead", idempotency_key: "lead_created:#{lead.id}"
        )
        submission.update!(lead_id: lead.id)
      end
    end
  end
end
