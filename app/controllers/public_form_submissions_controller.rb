class PublicFormSubmissionsController < ApplicationController
  def create
    @public_form = public_tenant.public_forms.active.find_by!(slug: params[:slug])
    submission = @public_form.submissions.new(
      payload: submission_payload,
      source: source_payload
    )

    if valid_required_fields?(submission.payload) && submission.save
      WebhookService.send_form_data(
        @public_form.webhook_origin,
        submission.payload.merge(
          public_form_id: @public_form.id,
          public_form_slug: @public_form.slug,
          public_form_name: @public_form.name,
          public_form_category: @public_form.category,
          page_url: source_payload[:page_url]
        ),
        request: request,
        tenant: public_tenant,
        public_form: @public_form
      )

      respond_to_success(submission)
    else
      respond_to_errors(submission)
    end
  end

  private

  def submission_payload
    raw = params.fetch(:public_form_submission, params.fetch(:submission, {}))
    raw_payload = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    allowed_names = @public_form.fields.map(&:name)

    @public_form.fields.each_with_object({}) do |field, payload|
      value = raw_payload[field.name]
      value = Array(value).reject(&:blank?) if field.field_type == "checkbox"
      value = Phones::Normalizer.call(value).to_s if field.field_type == "tel" && value.present?
      payload[field.name] = value if allowed_names.include?(field.name)
    end.compact
  end

  def valid_required_fields?(payload)
    @missing_required_fields = @public_form.fields.select do |field|
      field.required? && payload[field.name].blank?
    end

    @missing_required_fields.empty?
  end

  def source_payload
    {
      page_url: params[:page_url].presence || request.referer,
      request_url: request.original_url,
      referrer_url: request.referer,
      user_agent: request.user_agent,
      remote_ip: request.remote_ip,
      utm: request.query_parameters.slice(
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "gclid", "fbclid", "msclkid"
      ).compact_blank
    }.compact_blank
  end

  def respond_to_success(submission)
    payload = {
      success: true,
      message: @public_form.success_message,
      redirect_url: @public_form.redirect_url.presence,
      submission_id: submission.id
    }.compact

    respond_to do |format|
      format.json { render json: payload }
      format.html do
        redirect_to(@public_form.redirect_url.presence || request.referer || root_path, notice: @public_form.success_message, allow_other_host: true)
      end
    end
  end

  def respond_to_errors(submission)
    errors = submission.errors.full_messages
    errors += @missing_required_fields.map { |field| "#{field.label} é obrigatório." } if @missing_required_fields.present?
    errors = ["Revise os campos obrigatórios."] if errors.blank?

    respond_to do |format|
      format.json { render json: { success: false, errors: errors }, status: :unprocessable_entity }
      format.html { redirect_to(request.referer || root_path, alert: errors.to_sentence) }
    end
  end
end
