class Admin::WhatsappCampaignsController < Admin::BaseController
  before_action -> { check_permission!(:view, :whatsapp_campaigns) }, only: [:index, :show, :status, :documentation]
  before_action -> { check_permission!(:manage, :whatsapp_campaigns) }, except: [:index, :show, :status]
  before_action :set_campaign, only: [:show, :edit, :update, :destroy, :start, :pause, :resume, :cancel, :cancel_pending, :retry_failed, :status]
  before_action :load_options, only: [:new, :edit, :create, :update]

  def index
    WhatsappSenderNumber.sync_from_current_integration!(current_tenant) if current_tenant.whatsapp_sender_numbers.none?
    @selected_sender_number = current_tenant.whatsapp_sender_numbers.active.find_by(id: params[:whatsapp_sender_number_id])
    @number_selection_only = @selected_sender_number.blank?
    @filters = campaign_filters
    @sender_numbers = current_tenant.whatsapp_sender_numbers.ordered
    @campaign_groups = grouped_campaigns(base_campaign_scope)
    scoped = apply_campaign_filters(base_campaign_scope)
    @campaigns = scoped.recent.paginate(page: params[:page], per_page: 25)
    @dashboard = campaign_dashboard(scoped)
    @filter_options = campaign_filter_options
    @page_title = "Disparos WhatsApp"
  end

  def show
    @campaign.refresh_counters!
    @metrics = campaign_metrics
    @failure_summary = campaign_failure_summary
    @messages_status = params[:messages_status].to_s.presence
    @messages_query = params[:messages_query].to_s.strip.presence
    @messages = filtered_messages.paginate(page: params[:page], per_page: 30)
    @page_title = @campaign.name
  end

  def status
    @campaign.refresh_counters!
    @messages_status = params[:messages_status].to_s.presence
    @messages_query = params[:messages_query].to_s.strip.presence

    render json: campaign_live_status_payload
  end

  def documentation
    document_path = Rails.root.join("public/docs/whatsapp-campaigns-automation-distribution.pdf")

    unless File.exist?(document_path)
      redirect_to admin_whatsapp_campaigns_path(whatsapp_sender_number_id: params[:whatsapp_sender_number_id]),
                  alert: "Documentação do módulo ainda não foi gerada."
      return
    end

    send_file document_path,
              filename: "whatsapp-campanhas-automacao-distribuicao.pdf",
              type: "application/pdf",
              disposition: "inline"
  end

  def new
    @campaign = current_tenant.whatsapp_campaigns.new(
      send_rate: 50,
      status: "draft",
      whatsapp_sender_number_id: params[:whatsapp_sender_number_id].presence,
      whatsapp_template_id: params[:whatsapp_template_id].presence
    )
    @page_title = "Novo disparo WhatsApp"
  end

  def create
    @campaign = current_tenant.whatsapp_campaigns.new(campaign_params)
    @campaign.created_by = current_admin_user
    apply_submit_mode

    if @campaign.save
      Automation::WhatsappCampaignWorkflowSync.call(@campaign)
      @campaign.start! if params[:commit_action] == "start_now"
      schedule_campaign_start if params[:commit_action] == "schedule"
      redirect_to admin_whatsapp_campaign_path(@campaign), notice: "Disparo WhatsApp criado."
    else
      @page_title = "Novo disparo WhatsApp"
      render :new, status: :unprocessable_entity
    end
  end

  def preview_audience
    preview_campaign = current_tenant.whatsapp_campaigns.new(preview_campaign_params)
    preview_campaign.created_by = current_admin_user
    preview = Whatsapp::CampaignAudienceResolver.call(
      preview_campaign,
      materialize: false,
      uploaded_file: params.dig(:whatsapp_campaign, :audience_file)
    )

    render json: {
      ok: preview.ok?,
      mode: preview.mode,
      summary: preview.summary,
      errors: preview.errors,
      total: preview.total,
      valid_phone_count: preview.valid_phone_count,
      without_phone_count: preview.without_phone_count,
      invalid_count: preview.invalid_count,
      sample: preview.sample.map do |recipient|
        {
          id: recipient.respond_to?(:id) ? recipient.id : nil,
          name: recipient.display_name,
          phone: recipient.display_phone,
          email: recipient.respond_to?(:display_email) ? recipient.display_email : nil,
          origin: recipient.respond_to?(:origin) ? recipient.origin : nil,
          status: recipient.respond_to?(:status) ? recipient.status : nil,
          responsible: recipient.respond_to?(:admin_user) ? recipient.admin_user&.name : nil
        }
      end
    }
  end

  def preview_template
    template = current_tenant.whatsapp_templates.approved.find_by(id: params.dig(:whatsapp_campaign, :whatsapp_template_id))
    unless template
      render json: { ok: false, error: "Selecione um modelo aprovado." }, status: :unprocessable_content
      return
    end

    variables = clean_template_variables(params.dig(:whatsapp_campaign, :template_variables))
    suggestions = suggested_template_variables(template)
    effective_variables = suggestions.merge(variables)
    preview = Whatsapp::CampaignTemplatePreview.call(template: template, variables: effective_variables)
    render json: {
      ok: true,
      body: preview.body,
      values: preview.values,
      media: template_preview_media(template),
      variable_count: template.variable_count,
      suggested_variables: suggestions,
      variables_schema: template_variables_schema(template, effective_variables),
      buttons: template_buttons_schema(template, clean_response_decisions(params.dig(:whatsapp_campaign, :response_decisions)))
    }
  end

  def send_test
    template = current_tenant.whatsapp_templates.approved.find_by(id: params.dig(:whatsapp_campaign, :whatsapp_template_id))
    unless template
      render json: { ok: false, error: "Selecione um modelo aprovado." }, status: :unprocessable_entity
      return
    end

    result = Whatsapp::CampaignTestSender.call(
      template: template,
      phone: params[:test_phone],
      variables: clean_template_variables(params.dig(:whatsapp_campaign, :template_variables)),
      sender_number: current_tenant.whatsapp_sender_numbers.active.find_by(id: params.dig(:whatsapp_campaign, :whatsapp_sender_number_id)),
      admin_user: current_admin_user
    )
    status = result[:ok] ? :ok : :unprocessable_content
    render json: result, status: status
  end

  def edit
    @page_title = "Editar disparo WhatsApp"
  end

  def update
    @campaign.assign_attributes(campaign_params)
    apply_submit_mode

    if @campaign.save
      Automation::WhatsappCampaignWorkflowSync.call(@campaign)
      @campaign.start! if params[:commit_action] == "start_now"
      schedule_campaign_start if params[:commit_action] == "schedule"
      redirect_to admin_whatsapp_campaign_path(@campaign), notice: "Disparo WhatsApp atualizado."
    else
      @page_title = "Editar disparo WhatsApp"
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @campaign.processing?
      redirect_to admin_whatsapp_campaign_path(@campaign), alert: "Disparos em processamento precisam ser pausados ou cancelados antes de remover."
      return
    end

    @campaign.destroy
    redirect_to admin_whatsapp_campaigns_path, notice: "Disparo removido."
  end

  def start
    @campaign.start!
    redirect_to admin_whatsapp_campaign_path(@campaign), notice: "Disparo iniciado."
  rescue => e
    redirect_to admin_whatsapp_campaign_path(@campaign), alert: e.message
  end

  def pause
    @campaign.pause!
    redirect_to admin_whatsapp_campaign_path(@campaign), notice: "Disparo pausado."
  end

  def resume
    @campaign.resume!
    redirect_to admin_whatsapp_campaign_path(@campaign), notice: "Disparo retomado."
  end

  def cancel
    @campaign.cancel!
    redirect_to admin_whatsapp_campaign_path(@campaign), notice: "Disparo cancelado."
  end

  def cancel_pending
    count = @campaign.cancel_pending_messages!
    redirect_to admin_whatsapp_campaign_path(@campaign), notice: "#{count} envio(s) pendente(s) cancelado(s)."
  end

  def retry_failed
    count = @campaign.retry_failed_messages!
    redirect_to admin_whatsapp_campaign_path(@campaign), notice: "#{count} falha(s) reenfileirada(s)."
  rescue => e
    redirect_to admin_whatsapp_campaign_path(@campaign), alert: e.message
  end

  private

  def set_campaign
    @campaign = base_campaign_scope.find(params[:id])
  end

  def load_options
    @template_options = current_tenant.whatsapp_templates.approved.ordered.pluck(:name, :id)
    @status_options = Lead.status_options
    @origin_options = Lead.origin_options
    @tag_options = Lead.tag_options(scope: current_tenant.leads)
    @broker_options = current_tenant.admin_users.active.order(:name).pluck(:name, :id)
    @sender_number_options = current_tenant.whatsapp_sender_numbers.active.ordered.map { |number| [number.display_label, number.id] }
    @group_options = current_tenant.whatsapp_campaigns.where.not(group_name: [nil, ""]).distinct.order(:group_name).pluck(:group_name)
    @distribution_rule_options = current_tenant.distribution_rules.active.order(:name).pluck(:name, :id)
    @audience_field_options = Whatsapp::CampaignFilterConditions::FIELD_DEFINITIONS.map { |key, meta| [meta[:label], key] }
    @audience_operator_options = [
      ["Contém", "contains"],
      ["Igual", "equals"],
      ["Um destes", "in"],
      ["Preenchido", "present"],
      ["Vazio", "blank"],
      ["Entre datas", "between"],
      ["Desde", "since"],
      ["Até", "until"],
      ["Com essas tags", "with_any"],
      ["Sem essas tags", "without_any"]
    ]
  end

  def campaign_params
    permitted = params.require(:whatsapp_campaign).permit(
      :name,
      :description,
      :whatsapp_template_id,
      :whatsapp_sender_number_id,
      :group_name,
      :scheduled_at,
      :send_rate,
      :audience_mode,
      :audience_file,
      :import_batch_size,
      :import_interval_minutes,
      audience_filters: {},
      audience_definition: [
        :logic,
        { conditions: [:field, :operator, :value, :from, :to, { values: [] }] }
      ],
      template_variables: {},
      response_decisions: {
        buttons: [:key, :text, :kind, :action, :distribution_rule_id, :message]
      }
    )
    permitted[:audience_filters] = clean_audience_filters(permitted[:audience_filters])
    permitted[:audience_mode] = clean_audience_mode(permitted[:audience_mode])
    permitted[:audience_definition] = clean_audience_definition(permitted[:audience_definition])
    permitted[:template_variables] = clean_template_variables(permitted[:template_variables])
    permitted[:response_decisions] = clean_response_decisions(permitted[:response_decisions])
    permitted
  end

  def preview_campaign_params
    attrs = campaign_params
    attrs.delete(:audience_file)
    attrs[:whatsapp_template_id] ||= current_tenant.whatsapp_templates.approved.limit(1).pick(:id)
    attrs[:name] = attrs[:name].presence || "Preview de público"
    attrs
  end

  def clean_audience_mode(value)
    mode = value.to_s
    WhatsappCampaign::AUDIENCE_MODES.include?(mode) ? mode : "filters"
  end

  def clean_audience_definition(raw)
    data = parameter_hash(raw).with_indifferent_access
    conditions = parameter_array(data[:conditions]).filter_map do |item|
      condition = parameter_hash(item).with_indifferent_access
      field = condition[:field].to_s
      next if field.blank?

      values = Array(condition[:values]).presence || condition[:value].to_s.split(",")
      {
        field: field,
        operator: condition[:operator].to_s.presence,
        value: condition[:value].to_s.strip.presence,
        values: values.map { |value| value.to_s.strip }.reject(&:blank?),
        from: condition[:from].to_s.strip.presence,
        to: condition[:to].to_s.strip.presence
      }.compact
    end

    { logic: "and", conditions: conditions }
  end

  def clean_audience_filters(raw)
    data = parameter_hash(raw)
    {
      status: data["status"].presence,
      origin: data["origin"].presence,
      admin_user_id: data["admin_user_id"].presence
    }.compact
  end

  def clean_template_variables(raw)
    parameter_hash(raw).transform_values { |value| value.to_s.strip }.reject { |_key, value| value.blank? }
  end

  def clean_response_decisions(raw)
    data = parameter_hash(raw).with_indifferent_access
    rows = parameter_array(data[:buttons]).filter_map do |item|
      attrs = parameter_hash(item).with_indifferent_access
      key = attrs[:key].to_s.strip
      text = attrs[:text].to_s.strip
      action = attrs[:action].to_s
      next if key.blank? || text.blank?

      action = "ignore" unless WhatsappCampaign::RESPONSE_ACTIONS.key?(action)
      {
        key: key,
        text: text,
        kind: attrs[:kind].to_s.strip.presence,
        action: action,
        distribution_rule_id: attrs[:distribution_rule_id].to_s.strip.presence,
        message: attrs[:message].to_s.strip.presence
      }.compact
    end

    rows.present? ? { buttons: rows } : {}
  end

  def suggested_template_variables(template)
    template.variable_references.each_with_object({}) do |reference, result|
      result[reference[:index].to_s] = suggested_variable_for(reference[:context])
    end
  end

  def suggested_variable_for(context)
    window = context.to_s.downcase

    return "{{corretor_telefone}}" if window.match?(/(contato|telefone|celular|whats).*(agente|corretor|respons[aá]vel)|(?:agente|corretor|respons[aá]vel).*(contato|telefone|celular|whats)/)
    return "{{corretor_email}}" if window.match?(/e-?mail.*(agente|corretor|respons[aá]vel)|(?:agente|corretor|respons[aá]vel).*e-?mail/)
    return "{{corretor}}" if window.match?(/aqui\s+[ée]|agente respons[aá]vel|corretor|respons[aá]vel|consultor/)
    return "{{empresa}}" if window.match?(/\bda\s+\{\{|\bdo\s+\{\{|\bempresa|imobili[aá]ria|conta/)
    return "{{origem}}" if window.match?(/fonte|origem|canal|source/)
    return "{{telefone}}" if window.match?(/telefone|celular|whats|contato/)
    return "{{email}}" if window.match?(/e-?mail/)
    return "{{nome}}" if window.match?(/\A(ol[aá]|oi|bom dia|boa tarde|boa noite)\s+\{\{/)
    return "{{nome}}" if window.match?(/nome|cliente|lead/)
    return "{{status}}" if window.match?(/status|funil|etapa|converteu|convers[aã]o/)
    return "{{observacoes}}" if window.match?(/obs|observa|informa|info|detalhe/)
    return "{{tags}}" if window.match?(/tag|etiqueta|marcador/)
    return "{{produto}}" if window.match?(/produto|im[oó]vel|empreendimento/)

    ""
  end

  def template_variables_schema(template, variables)
    template.variable_references.map do |reference|
      index = reference[:index].to_i
      {
        index: index,
        placeholder: reference[:placeholder],
        context: reference[:context],
        selected: variables[index.to_s].to_s
      }
    end
  end

  def template_buttons_schema(template, decisions)
    configured = decisions.with_indifferent_access.dig(:buttons)
    configured = configured.values if configured.is_a?(Hash)
    configured_by_key = Array(configured).each_with_object({}) do |row, memo|
      attrs = row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row.to_h
      memo[attrs["key"].to_s] = attrs.with_indifferent_access
    end

    template.interactive_buttons.map do |button|
      decision = configured_by_key[button["key"].to_s] || {}
      action = decision[:action].presence || default_response_action_for(button["text"])
      button.merge(
        "action" => action,
        "action_label" => WhatsappCampaign::RESPONSE_ACTIONS.fetch(action, WhatsappCampaign::RESPONSE_ACTIONS["ignore"]),
        "distribution_rule_id" => decision[:distribution_rule_id].to_s,
        "message" => decision[:message].to_s
      )
    end
  end

  def template_preview_media(template)
    header = Array(template.components).find { |component| template_component_value(component, "type").to_s.upcase == "HEADER" }
    format = template_component_value(header, "format").to_s.downcase.presence
    format = template.header_format.to_s if format.blank? || format == "text"
    return nil if format.blank? || format == "none" || format == "text"

    url = template_preview_media_url(template, header)
    {
      type: format,
      label: template_preview_media_label(format),
      url: url,
      available: url.present?
    }
  end

  def template_preview_media_label(format)
    {
      "image" => "Imagem",
      "video" => "Vídeo",
      "audio" => "Áudio",
      "document" => "Documento"
    }[format] || WhatsappTemplate::HEADER_FORMATS[format] || format.humanize
  end

  def template_preview_media_url(template, header)
    return Rails.application.routes.url_helpers.rails_blob_path(template.header_media_file, only_path: true) if template.header_media_file.attached?

    example = template_component_value(header, "example")
    handle = template.header_media_handle.presence || Array(template_component_value(example, "header_handle")).first.to_s
    return handle if handle.match?(%r{\Ahttps?://}i)

    nil
  end

  def template_component_value(component, key)
    return nil if component.blank?

    component[key] || component[key.to_sym]
  end

  def default_response_action_for(text)
    normalized = text.to_s.downcase
    return "unsubscribe" if normalized.match?(/descadastr|sair|parar|stop/)
    return "mark_no_interest" if normalized.match?(/sem interesse|não tenho interesse|nao tenho interesse|bloquear/)
    return "generate_lead" if normalized.match?(/saiba|quero|interesse|atendimento|falar|mais/)

    "ignore"
  end

  def template_variable_context(body, placeholder)
    line = body.to_s.lines.find { |item| item.include?(placeholder) }.to_s.strip
    return "Variável #{placeholder}" if line.blank?
    return line unless line.scan(/\{\{\d+\}\}/).size > 1

    fragment_for_placeholder(line, placeholder).presence || line
  end

  def fragment_for_placeholder(line, placeholder)
    position = line.index(placeholder)
    return nil unless position

    start_index = [line.rindex(/[\.\!\?\n]/, position)&.+(1), previous_placeholder_end(line, position), 0].compact.max
    next_punctuation = line.index(/[\.\!\?]/, position + placeholder.length)
    next_placeholder = line.index(/\{\{\d+\}\}/, position + placeholder.length)
    end_index = [next_punctuation&.+(1), next_placeholder, line.length].compact.min

    line[start_index...end_index].to_s.strip.gsub(/\s+/, " ")
  end

  def previous_placeholder_end(line, position)
    previous_start = nil
    line.to_enum(:scan, /\{\{\d+\}\}/).each do
      match_start = Regexp.last_match.begin(0)
      break if match_start >= position

      previous_start = Regexp.last_match.end(0)
    end
    previous_start
  end

  def parameter_hash(raw)
    return {} if raw.blank?
    return raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)

    raw.to_h
  end

  def parameter_array(raw)
    value = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
    return value.values if value.is_a?(Hash)

    Array(value)
  end

  def base_campaign_scope
    scope = current_tenant.whatsapp_campaigns.includes(:whatsapp_template, :created_by, :whatsapp_sender_number)
    owner_ids = visible_owner_ids(:whatsapp_campaigns)
    scope = scope.where(created_by_id: owner_ids) if owner_ids.present?
    scope = scope.where(whatsapp_sender_number_id: @selected_sender_number.id) if @selected_sender_number
    scope
  end

  def campaign_filters
    {
      status: params[:status].to_s.presence,
      created_by_id: params[:created_by_id].to_s.presence,
      whatsapp_template_id: params[:whatsapp_template_id].to_s.presence,
      whatsapp_sender_number_id: @selected_sender_number&.id&.to_s || params[:whatsapp_sender_number_id].to_s.presence,
      group_name: params[:group_name].to_s.presence,
      query: params[:query].to_s.strip.presence,
      started_on: params[:started_on].to_s.presence,
      ended_on: params[:ended_on].to_s.presence
    }.compact
  end

  def apply_campaign_filters(scope)
    filters = @filters || campaign_filters
    scope = scope.where(status: filters[:status]) if WhatsappCampaign::STATUSES.include?(filters[:status])
    scope = scope.where(created_by_id: filters[:created_by_id]) if filters[:created_by_id].present?
    scope = scope.where(whatsapp_template_id: filters[:whatsapp_template_id]) if filters[:whatsapp_template_id].present?
    scope = scope.where(whatsapp_sender_number_id: filters[:whatsapp_sender_number_id]) if filters[:whatsapp_sender_number_id].present?
    scope = scope.where(group_name: filters[:group_name]) if filters[:group_name].present?
    scope = scope.where("whatsapp_campaigns.name ILIKE ?", "%#{filters[:query]}%") if filters[:query].present?
    scope = scope.where("whatsapp_campaigns.created_at >= ?", Date.parse(filters[:started_on]).beginning_of_day) if filters[:started_on].present?
    scope = scope.where("whatsapp_campaigns.created_at <= ?", Date.parse(filters[:ended_on]).end_of_day) if filters[:ended_on].present?
    scope
  rescue Date::Error
    scope
  end

  def campaign_filter_options
    {
      statuses: WhatsappCampaign::STATUSES.map { |status| [status.humanize, status] },
      creators: current_tenant.admin_users.active.order(:name).pluck(:name, :id),
      templates: current_tenant.whatsapp_templates.order(:name).pluck(:name, :id),
      senders: current_tenant.whatsapp_sender_numbers.active.ordered.map { |number| [number.display_label, number.id] },
      groups: current_tenant.whatsapp_campaigns.where.not(group_name: [nil, ""]).distinct.order(:group_name).pluck(:group_name)
    }
  end

  def grouped_campaigns(scope)
    scope
      .where.not(group_name: [nil, ""])
      .group(:group_name)
      .select(
        :group_name,
        "COUNT(*) AS campaigns_count",
        "SUM(total_recipients) AS total_recipients_sum",
        "SUM(sent_count) AS sent_count_sum",
        "SUM(failed_count) AS failed_count_sum",
        "SUM(replied_count) AS replied_count_sum"
      )
      .order(:group_name)
  end

  def campaign_dashboard(scope)
    totals_scope = scope.except(:includes, :preload, :eager_load, :order)
    totals = totals_scope.pick(
      Arel.sql("COALESCE(SUM(total_recipients), 0)"),
      Arel.sql("COALESCE(SUM(sent_count), 0)"),
      Arel.sql("COALESCE(SUM(failed_count), 0)"),
      Arel.sql("COALESCE(SUM(replied_count), 0)"),
      Arel.sql("COALESCE(SUM(delivered_count), 0)"),
      Arel.sql("COALESCE(SUM(read_count), 0)")
    )
    total, sent, failed, replied, delivered, read = totals.map(&:to_i)
    cost = @selected_sender_number&.campaign_cost(sent_count: sent, failed_count: failed) ||
           ((sent * 0.59.to_d) + (failed * 0.12.to_d))
    {
      active: totals_scope.active.count,
      total: total,
      sent: sent,
      failed: failed,
      replied: replied,
      delivered: delivered,
      read: read,
      attended: replied,
      unattended: [sent - replied - failed, 0].max,
      delivery_rate: percent(delivered, sent),
      read_rate: percent(read, sent),
      reply_rate: percent(replied, sent),
      cpl: replied.positive? ? cost / replied : 0.to_d,
      cost: cost
    }
  end

  def apply_submit_mode
    case params[:commit_action]
    when "schedule"
      @campaign.status = "scheduled"
    when "start_now"
      @campaign.status = "draft" if @campaign.status.blank?
    end
  end

  def schedule_campaign_start
    return if @campaign.scheduled_at.blank?

    Whatsapp::CampaignStartJob
      .set(wait_until: @campaign.scheduled_at)
      .perform_later(@campaign.id, tenant_id: @campaign.tenant_id)
  end

  def filtered_messages
    scope = @campaign.campaign_messages.includes(:lead, :whatsapp_campaign_recipient).order(created_at: :desc)
    scope =
      if @messages_status == WhatsappCampaignMessage::DELIVERY_UNCONFIRMED_STATUS
        scope.delivery_unconfirmed
      elsif WhatsappCampaignMessage::STATUSES.include?(@messages_status)
        scope.where(status: @messages_status)
      else
        scope
      end

    if @messages_query.present?
      digits = @messages_query.gsub(/\D/, "")
      scope = scope.left_joins(:lead, :whatsapp_campaign_recipient).where(
        "leads.name ILIKE :query OR whatsapp_campaign_recipients.name ILIKE :query OR whatsapp_campaign_messages.phone_number ILIKE :phone",
        query: "%#{@messages_query}%",
        phone: "%#{digits.presence || @messages_query}%"
      )
    end

    scope
  end

  def campaign_metrics
    total = @campaign.total_recipients.to_i
    sent = @campaign.sent_count.to_i
    delivered = @campaign.delivered_count.to_i
    read = @campaign.read_count.to_i
    replied = @campaign.replied_count.to_i
    failed = @campaign.failed_count.to_i
    cost = @campaign.estimated_cost
    {
      total: total,
      sent: sent,
      delivered: delivered,
      read: read,
      replied: replied,
      failed: failed,
      attended: @campaign.attended_count,
      unattended: @campaign.unattended_count,
      cost: cost,
      cpl: @campaign.estimated_cpl,
      delivery_rate: percent(delivered, sent),
      read_rate: percent(read, sent),
      reply_rate: percent(replied, sent),
      failure_rate: percent(failed, total)
    }
  end

  def campaign_live_status_payload
    metrics = campaign_metrics
    progress = campaign_progress(metrics)
    {
      status: @campaign.status,
      status_label: @campaign.status.humanize,
      status_tone: campaign_status_tone(@campaign),
      active: @campaign.processing? || @campaign.scheduled?,
      next_poll_interval_ms: campaign_status_poll_interval_ms,
      updated_at: l(@campaign.updated_at, format: :short),
      progress_percent: progress[:percent],
      pending_count: progress[:pending_count],
      metrics: metrics,
      response_cards: @campaign.dynamic_response_cards,
      failure_summary: campaign_failure_summary,
      recent_messages: recent_campaign_messages
    }
  end

  def campaign_progress(metrics = campaign_metrics)
    total = metrics[:total].to_i
    done = metrics[:sent].to_i + metrics[:failed].to_i
    {
      percent: total.positive? ? percent(done, total) : 0,
      pending_count: [total - done, 0].max
    }
  end

  def recent_campaign_messages
    filtered_messages.limit(30).map do |message|
      {
        recipient_name: message.display_name,
        recipient_url: message.lead ? admin_lead_path(message.lead) : nil,
        lead_name: message.display_name,
        lead_url: message.lead ? admin_lead_path(message.lead) : nil,
        phone_number: message.phone_number,
        external_message_id: message.external_message_id,
        status: message.display_status_key,
        status_label: message.display_status_label,
        status_tone: message_status_tone(message),
        response_status: message.response_status_key,
        response_status_label: message.response_status_label,
        response_status_tone: message.response_status_tone,
        response_status_note: message.response_status_note,
        failure_reason: message.status_note,
        updated_at: l(message.updated_at, format: :short)
      }
    end
  end

  def campaign_status_tone(campaign)
    return "red" if campaign.failed? || campaign.cancelled?
    return "green" if campaign.completed?
    return "amber" if campaign.processing? || campaign.scheduled? || campaign.paused?

    "gray"
  end

  def message_status_tone(message)
    return "red" if message.failed? || message.cancelled?
    return "amber" if message.delivery_unconfirmed?
    return "green" if message.replied? || message.delivered? || message.read?
    return "blue" if message.sent?

    "gray"
  end

  def campaign_status_poll_interval_ms
    return 3_000 if @campaign.processing? || @campaign.scheduled?

    nil
  end

  def campaign_failure_summary
    failed_scope = @campaign.campaign_messages.where(status: %w[failed cancelled])
    failed_count = @campaign.campaign_messages.failed.count
    cancelled_count = @campaign.campaign_messages.where(status: "cancelled").count
    reason_rows = normalize_failure_reasons(failed_scope.group(:failure_reason).count)
    latest_message = failed_scope.order(failed_at: :desc, updated_at: :desc).first
    latest_details = latest_message&.failure_reason_details || {}
    severity_counts = reason_rows.each_with_object(Hash.new(0)) do |row, memo|
      memo[row[:severity].to_s] += row[:count].to_i
    end

    {
      count: failed_scope.count,
      failed_count: failed_count,
      cancelled_count: cancelled_count,
      tone: severity_counts["error"].positive? ? "error" : "warning",
      severity_counts: severity_counts,
      reasons: reason_rows.first(5),
      latest: latest_message ? latest_details.merge(failed_at: latest_message.failed_at || latest_message.updated_at) : nil,
      next_retry_at: failed_scope.where.not(next_retry_at: nil).minimum(:next_retry_at),
      retryable_count: failed_scope.ready_for_retry.count,
      pending_retry_count: failed_scope.where.not(next_retry_at: nil).where("next_retry_at > ?", Time.current).count
    }
  end

  def normalize_failure_reasons(raw_reasons)
    raw_reasons.each_with_object({}) do |(reason, count), memo|
      details = WhatsappCampaignMessage.normalize_failure_reason(reason)
      key = details[:group_key]
      memo[key] ||= details.merge(count: 0)
      memo[key][:count] += count.to_i
    end.values.sort_by { |item| [-item[:count].to_i, item[:label].to_s] }
  end

  def percent(part, total)
    return 0 if total.to_i.zero?

    ((part.to_f / total.to_f) * 100).round(1)
  end
end
