class PublicFormSubmissionsController < ApplicationController
  def create
    @public_form = public_tenant.public_forms.active.find_by!(slug: params[:slug])
    uploads = file_uploads
    submission = @public_form.submissions.new(
      payload: submission_payload.merge(uploads.transform_values { |files| files.map(&:original_filename) }),
      source: source_payload
    )

    if @file_errors.empty? && valid_required_fields?(submission.payload) && store_files(submission, uploads) && submission.save
      webhook_options = { request: request, tenant: public_tenant, public_form: @public_form }
      webhook_options[:url] = @public_form.webhook_url if @public_form.webhook_url.present?
      WebhookService.send_form_data(
        @public_form.webhook_origin,
        submission.payload.merge(
          public_form_id: @public_form.id,
          public_form_slug: @public_form.slug,
          public_form_name: @public_form.name,
          public_form_category: @public_form.category,
          page_url: source_payload[:page_url]
        ),
        webhook_options
      )
      PublicFormLeadRoutingJob.perform_later(submission.id) if @public_form.routes_to_distribution?

      respond_to_success(submission)
    else
      @stored_blobs.to_a.each(&:purge)
      respond_to_errors(submission)
    end
  end

  private

  def submission_payload
    raw = params.fetch(:public_form_submission, params.fetch(:submission, {}))
    raw_payload = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    allowed_names = @public_form.fields.map(&:name)

    @public_form.fields.each_with_object({}) do |field, payload|
      next if field.file_field?

      value = raw_payload[field.name]
      value = Array(value).reject(&:blank?) if field.field_type == "checkbox"
      # Campo com máscara: o valor tem que estar no formato definido (o navegador já exige, aqui é a garantia).
      # Vazio passa (obrigatoriedade é outra regra); telefone é conferido antes da normalização.
      if field.mask? && value.present? && !field.mask_match?(value.to_s.strip)
        @file_errors << "#{field.label}: use o formato #{field.mask_hint}."
        next
      end
      value = Phones::Normalizer.call(value).to_s if field.field_type == "tel" && value.present?
      payload[field.name] = value if allowed_names.include?(field.name)
    end.compact
  end

  # Arquivos válidos por campo (extensão, tamanho e quantidade conforme a config do campo).
  def file_uploads
    @file_errors = []
    raw = params.fetch(:public_form_submission, params.fetch(:submission, {}))
    raw = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h

    @public_form.fields.select(&:file_field?).each_with_object({}) do |field, uploads|
      files = Array(raw[field.name]).select { |file| file.respond_to?(:original_filename) && file.size.positive? }
      next if files.empty?

      if files.size > field.file_max_files
        @file_errors << "#{field.label}: envie no máximo #{field.file_max_files} arquivo(s)."
      elsif (invalid = files.find { |file| invalid_file?(field, file) })
        @file_errors << "#{field.label}: #{invalid.original_filename} não é permitido (#{field.file_summary})."
      else
        uploads[field.name] = files
      end
    end
  end

  def invalid_file?(field, file)
    extension = File.extname(file.original_filename.to_s).delete_prefix(".").downcase
    !field.file_extensions.include?(extension) || file.size > field.file_max_mb.megabytes
  end

  # Sobe para o storage de documentos configurado na conta (Spaces, S3 ou local).
  def store_files(submission, uploads)
    return true if uploads.empty?

    blobs = @stored_blobs = []
    service_name = StorageIntegrationSetting.current(tenant: public_tenant).document_service_name
    uploads.each do |field_name, files|
      files.each do |file|
        blobs << Storage::BlobFactory.create_from_upload!(
          file,
          service_name: service_name,
          key_prefix: ["tenants", public_tenant.id, "public_forms", @public_form.slug, field_name].join("/"),
          metadata: { "identified" => true, "source" => "public_form", "privacy" => "private", "tenant_id" => public_tenant.id }
        )
      end
    end
    submission.files.attach(blobs)
    true
  rescue StandardError => e
    Rails.logger.error("[PublicFormSubmissions] falha ao armazenar arquivo do formulário #{@public_form.slug}: #{e.class}")
    blobs.each(&:purge)
    blobs.clear
    @file_errors << "Não foi possível enviar o arquivo. Tente novamente."
    false
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
    errors = @file_errors.to_a + submission.errors.full_messages
    errors += @missing_required_fields.map { |field| "#{field.label} é obrigatório." } if @missing_required_fields.present?
    errors = ["Revise os campos obrigatórios."] if errors.blank?

    respond_to do |format|
      format.json { render json: { success: false, errors: errors }, status: :unprocessable_entity }
      format.html { redirect_to(request.referer || root_path, alert: errors.to_sentence) }
    end
  end
end
