class MetaSyncEnabledIntegrationsJob < ApplicationJob
  queue_as :sync

  PROCESSING_TIMEOUT = 30.minutes

  def perform
    reconcile_observed_lead_forms

    UserMetaIntegration.find_each do |integration|
      next unless syncable?(integration)

      MetaSyncJob.perform_later(integration.id)
    end
  end

  private

  def syncable?(integration)
    integration.access_token.present? &&
      !integration.expired? &&
      !recently_processing?(integration)
  end

  def recently_processing?(integration)
    integration.sync_status == "processing" &&
      integration.updated_at.present? &&
      integration.updated_at > PROCESSING_TIMEOUT.ago
  end

  def reconcile_observed_lead_forms
    DistributionRule.where(auto_add_forms: true, source_meta: true).find_each do |rule|
      page_ids = Array(rule.meta_page_ids).compact_blank.map(&:to_s)
      next if page_ids.empty?

      observed_pairs = rule.tenant.leads
        .where("other_information ->> 'meta_page_id' IN (?)", page_ids)
        .where("other_information ? 'meta_form_id'")
        .distinct
        .pluck(
          Arel.sql("other_information ->> 'meta_page_id'"),
          Arel.sql("other_information ->> 'meta_form_id'")
        )
      observed_forms = observed_pairs.map(&:second).compact_blank.map(&:to_s).uniq

      add_forms_to_rule(rule, observed_forms)
      ensure_observed_form_records(observed_pairs)
    end
  end

  def add_forms_to_rule(rule, form_ids)
    current_forms = Array(rule.meta_forms).compact_blank.map(&:to_s)
    missing_forms = form_ids - current_forms
    return if missing_forms.empty?

    rule.update!(meta_forms: current_forms + missing_forms)
  end

  def ensure_observed_form_records(observed_pairs)
    observed_pairs.each do |page_id, form_id|
      form_id = form_id.to_s.presence
      page_id = page_id.to_s.presence
      next if page_id.blank? || form_id.blank?
      next if MetaLeadForm.exists?(form_id: form_id)

      page = MetaFacebookPage.find_by(page_id: page_id)
      next unless page

      page.meta_lead_forms.create!(
        form_id: form_id,
        name: "Meta Lead (#{form_id})",
        active: true
      )
    rescue ActiveRecord::RecordNotUnique
      next
    end
  end
end
