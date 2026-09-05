class Support::TicketsController < Support::BaseController
  before_action :load_ticket, only: [:show, :update, :messages, :notes, :access, :attachment, :revise_message, :remove_message]
  before_action :require_operator!, only: [:update, :notes, :access, :revise_message, :remove_message]

  def updates
    if params[:ticket_id].present?
      ticket = visible_tickets.find(params[:ticket_id])
      render json: { version: "#{ticket.revision}:#{ticket.messages.count}:#{ticket.pending?}" }
    else
      # O lembrete é pessoal, mesmo quando o proprietário consulta chamados da equipe.
      own = support_operator? ? Support::Ticket.none : support_account.tickets.where(requester_id: current_admin_user.id.to_s)
      unread = own.where("EXISTS (SELECT 1 FROM support_messages m WHERE m.ticket_id = support_tickets.id AND m.side = 'support' AND m.internal = false AND m.created_at > COALESCE(support_tickets.read_at, support_tickets.created_at)) OR support_tickets.resolved_at > COALESCE(support_tickets.read_at, support_tickets.created_at)")
      awaiting = own.where(status: "aguardando_usuario")
      open = own.where.not(status: "resolvido")
      ticket = unread.order(updated_at: :desc).first || awaiting.order(updated_at: :desc).first || open.order(updated_at: :desc).first
      render json: { count: unread.count, awaiting_count: awaiting.count, open_count: open.count,
        state: ticket ? "#{ticket.uid}:#{ticket.revision}:#{unread.count}:#{awaiting.count}" : nil,
        resolved: ticket&.resolved?, ticket_id: ticket&.id, url: ticket ? support_ticket_path(ticket) : support_tickets_path }

    end
  end

  def index
    if support_operator? && request.query_parameters.empty? && current_staff.queue_preferences.present?
      return redirect_to support_tickets_path(current_staff.queue_preferences)
    end
    @tickets = visible_tickets.includes(:account)
    @tickets = @tickets.where(origin: params[:origin]) if %w[ativo receptivo].include?(params[:origin])
    begin
      @tickets = @tickets.where('support_tickets.created_at >= ?', Date.iso8601(params[:from]).in_time_zone.beginning_of_day) if params[:from].present?
      @tickets = @tickets.where('support_tickets.created_at <= ?', Date.iso8601(params[:to]).in_time_zone.end_of_day) if params[:to].present?
    rescue Date::Error
      @tickets = @tickets.none
      flash.now[:alert] = 'Informe datas válidas.'
    end
    @tickets = support_operator? ? @tickets.order(created_at: params[:order] == 'newest' ? :desc : :asc, id: params[:order] == 'newest' ? :desc : :asc) : @tickets.order(updated_at: :desc)
    @tickets = @tickets.where(status: %w[aberto em_atendimento]) if params[:queue] == 'waiting_support'
    @tickets = @tickets.where(assignee_id: nil).where.not(status: 'resolvido') if support_operator? && params[:queue] == 'unassigned'
    @tickets = @tickets.where(status: params[:status]) if Support::Ticket::STATUSES.include?(params[:status])
    @tickets = @tickets.where(priority: params[:priority]) if Support::Ticket::PRIORITIES.include?(params[:priority])
    @tickets = @tickets.where(account_id: params[:account_id]) if support_operator? && params[:account_id].present?
    @tickets = @tickets.where(assignee_id: current_staff.id) if support_operator? && params[:mine] == "1"
    if params[:q].present?
      @tickets = @tickets.where("subject ILIKE :term OR requester_name ILIKE :term OR requester_email ILIKE :term OR uid = :uid OR support_tickets.id = :id", term: "%#{Support::Ticket.sanitize_sql_like(params[:q].to_s.first(100))}%", uid: params[:q], id: params[:q].to_s.delete_prefix('#').match?(/\A\d+\z/) ? params[:q].to_s.delete_prefix('#').to_i : -1)
    end
    @total = @tickets.count
    if support_operator?
      @label_catalog = SupportLabel.all.index_by { |label| label.name.downcase }
      @assignment_operators = Staff.where(role: %w[admin suporte]).order(:name).to_a
      @operators = @assignment_operators.select(&:active?)
    end
    @presence = StaffSession.where(ended_at: nil).where('expires_at > ? AND last_seen_at >= ?', Time.current, StaffSession::LEASE.ago).distinct.pluck(:staff_id) if support_operator?
    @page = [params[:page].to_i, 1].max
    if support_operator?
      if params[:after].present?
        anchor = visible_tickets.find(params[:after])
        comparison = params[:order] == 'newest' ? '<' : '>'
        @tickets = @tickets.where("(support_tickets.created_at, support_tickets.id) #{comparison} (?, ?)", anchor.created_at, anchor.id)
      end
      @tickets = @tickets.limit(31).to_a
      @has_more = @tickets.size > 30
      @tickets = @tickets.first(30)
    else
      @tickets = @tickets.limit(30).offset((@page - 1) * 30)
    end
  end

  def new
    return head :forbidden if support_operator?
    @ticket = support_account.tickets.new(intake: {})
    @screens = Support::Intake.screens(view_context)
    @ticket.source_path = safe_source_path
    @ticket.intake["menu_module"] = @screens.select { |_, path| @ticket.source_path.to_s == path || @ticket.source_path.to_s.start_with?("#{path}/") }.max_by { |_, path| path.length }&.first
    if (previous = visible_tickets.find_by(uid: params[:previous]))
      @ticket.previous_uid = previous.uid
      @ticket.subject = "Continuação: #{previous.subject}".first(180)
      @ticket.intake = previous.intake.merge("actual_result" => "")
    end
  end

  def create
    return head :forbidden if support_operator?
    @ticket = support_account.tickets.new(params.require(:support_ticket).permit(:subject, :source_path, :previous_uid, intake: Support::Ticket::QUESTIONS.keys))
    if params[:intake_choices]
      return head :bad_request unless params[:intake_choices].is_a?(ActionController::Parameters) && (params[:intake_details].nil? || params[:intake_details].is_a?(ActionController::Parameters))
      @screens = Support::Intake.screens(view_context)
      @ticket.intake = Support::Intake.normalize(params[:intake_choices].to_unsafe_h, params[:intake_details]&.to_unsafe_h || {}, @screens)
      @ticket.subject = [@ticket.intake['menu_module'], @ticket.intake['actual_result']].reject(&:blank?).join(' — ').first(180)
    end
    @ticket.assign_attributes(requester_id: current_admin_user.id.to_s, requester_name: current_admin_user.name, requester_email: current_admin_user.email)
    @ticket.source_path = @ticket.source_path.to_s.split(/[?#]/).first.to_s.first(250)
    @ticket.source_path = nil unless @ticket.source_path.start_with?("/admin") && !@ticket.source_path.start_with?("//")
    @ticket.previous_uid = visible_tickets.find_by(uid: @ticket.previous_uid)&.uid
    context = Rails.application.message_verifier(:support_context).verified(params[:context_token].to_s, purpose: :intake)
    context = nil unless context && context['user_id'] == current_admin_user.id && context['tenant_id'] == current_tenant.id
    @ticket.source_path = context['path'] if context
    @ticket.diagnostics = { 'context_verified' => context.present?, 'page_url' => request.base_url + @ticket.source_path.to_s, 'request_id' => request.request_id, 'recorded_at' => Time.current.iso8601 }
    @ticket.diagnostics['recent_errors'] = related_errors

    Support::Ticket.transaction do
      @ticket.save!
      message = @ticket.messages.create!(side: "requester", author: current_admin_user.name, body: @ticket.intake["actual_result"], files: uploaded_files)
      Support::Timeline.record!(@ticket, "support_message", staff: current_staff) if support_operator?
      Support::Exchange.enqueue(@ticket, message: message, command: "create")
    end
    kick_delivery
    if params[:modal] == "1"
      render :created, status: :created
    else
      redirect_to support_ticket_path(@ticket), notice: "Chamado registrado. Você pode acompanhar por aqui."
    end
  rescue ActiveRecord::RecordInvalid => error
    @ticket.errors.add(:base, error.record.errors.full_messages.to_sentence)
    @screens ||= Support::Intake.screens(view_context)
    render :new, status: :unprocessable_entity
  end

  def show
    @messages = @ticket.messages.where(internal: false).with_attached_files
    @notes = @ticket.messages.where(internal: true) if support_operator?
    @ticket.update_column(:read_at, Time.current) if !support_operator? && @ticket.requester_id == current_admin_user.id.to_s
    @operators = Staff.where(active: true, role: %w[admin suporte]).order(:name) if support_operator?
    @timeline = Support::TicketEvent.where(ticket_id: @ticket.id).includes(:staff).order(:occurred_at, :id).to_a if support_operator?
    @timing = Support::Timeline.measure(@ticket, @timeline) if support_operator?
    if support_operator?
      @audits = Support::Audit.where(ticket_id: @ticket.id).order(created_at: :desc).limit(50).to_a
      ids = @audits.flat_map { |audit| [audit.actor.to_s.delete_prefix('staff:').to_i, *Array(audit.details['assignee_id'])] }
      ids.concat(@timeline.flat_map { |event| Array(event.details.dig('changes', 'assignee_id')) })
      @audit_staff_names = Staff.where(id: ids.compact).pluck(:id, :name).to_h
    end
  end

  def messages
    return head :forbidden unless @ticket.account.active?
    return head :forbidden if !support_operator? && @ticket.requester_id != current_admin_user.id.to_s
    @ticket.with_lock do
      message = @ticket.messages.create!(side: support_operator? ? "support" : "requester", author: support_operator? ? current_staff.name : current_admin_user.name, author_staff_id: support_operator? ? current_staff.id : nil, body: params[:body], files: uploaded_files)
      if support_operator?
        @ticket.update!(first_response_at: @ticket.first_response_at || Time.current, status: "aguardando_usuario", assignee_id: @ticket.assignee_id || current_staff.id, assignee_name: @ticket.assignee_name || current_staff.name, revision: @ticket.revision + 1)
      else
        @ticket.touch
      end
      Support::Timeline.record!(@ticket, "support_message", staff: current_staff) if support_operator?
      Support::Exchange.enqueue(@ticket, message: message, command: support_operator? ? nil : "message")
    end
    kick_delivery
    redirect_to support_ticket_path(@ticket), notice: "Mensagem registrada."
  rescue ActiveRecord::RecordInvalid => error
    show
    @reply = params[:body]
    flash.now[:alert] = error.record.errors.full_messages.to_sentence
    render :show, status: :unprocessable_entity
  end

  def update
    return head :forbidden if params.require(:support_ticket).key?(:assignee_id) && !current_staff.admin?
    @ticket.with_lock do
      attrs = params.require(:support_ticket).permit(:status, :priority, :labels)
      if params[:support_ticket].key?(:assignee_id)
        staff = Staff.where(active: true, role: %w[admin suporte]).find_by(id: params[:support_ticket][:assignee_id])
        return head :unprocessable_entity if params[:support_ticket][:assignee_id].present? && !staff
        attrs.merge!(assignee_id: staff&.id, assignee_name: staff&.name)
      end
      attrs[:resolved_at] = Time.current if attrs[:status] == "resolvido"
      @ticket.update!(attrs.merge(revision: @ticket.revision + 1))
      Support::Audit.create!(account_id: @ticket.account_id, ticket_id: @ticket.id, actor: actor, action: "ticket_updated", details: @ticket.previous_changes.slice("status", "priority", "labels", "assignee_id"))
      Support::Timeline.record!(@ticket, "updated", staff: current_staff, details: { "changes" => @ticket.previous_changes.slice("status", "priority", "assignee_id") })
      Support::Exchange.enqueue(@ticket)
    end
    kick_delivery
    redirect_to support_ticket_path(@ticket), notice: "Chamado atualizado."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to support_ticket_path(@ticket), alert: error.record.errors.full_messages.to_sentence
  end

  def notes
    @ticket.with_lock do
      @ticket.messages.create!(side: "support", author: current_staff.name, body: params[:body], internal: true)
      Support::Timeline.record!(@ticket, "internal_note", staff: current_staff)
    end
    redirect_to support_ticket_path(@ticket), notice: "Nota interna adicionada."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to support_ticket_path(@ticket), alert: error.record.errors.full_messages.to_sentence
  end

  def access
    return head :forbidden unless @ticket.account.active?
    grant = Support::Transport.post(@ticket.account, "/internal/support/v1/access", { ticket_uid: @ticket.uid, operator_id: current_staff.id.to_s, operator_name: current_staff.name })
    Support::Audit.create!(account_id: @ticket.account_id, ticket_id: @ticket.id, actor: actor, action: "access_requested")
    @handoff_token = grant.fetch("token")
    @handoff_url = URI.join(@ticket.account.endpoint, "/support/access").to_s
    render :access
  rescue Support::Transport::DeliveryError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, JSON::ParserError, KeyError
    redirect_to support_ticket_path(@ticket), alert: "Não foi possível abrir a conta. Tente novamente."
  end

  def revise_message
    change_message(false)
  end

  def remove_message
    change_message(true)
  end

  def attachment
    message = @ticket.messages.where(internal: false).find_by!(uid: params[:message])
    raise ActiveRecord::RecordNotFound if message.deleted_at?
    file = message.files.find(params[:file])
    response.set_header("Cache-Control", "private, no-store")
    send_data file.download, filename: file.filename.to_s, type: file.content_type, disposition: (params[:preview] == "1" && (file.content_type.start_with?("image/") || Support::Message::AUDIO_TYPES.include?(file.content_type)) ? "inline" : "attachment")
  end

  private
  def change_message(remove)
    @ticket.with_lock do
      message = @ticket.messages.where(side: 'support', internal: false, deleted_at: nil).find_by!(uid: params[:message_uid])
      return head :forbidden unless current_staff.admin? || message.author_staff_id == current_staff.id
      raise ActiveRecord::RecordInvalid, @ticket if @ticket.resolved?
      before = message.body
      message.update!(body: remove ? 'Mensagem removida.' : params[:body], edited_at: Time.current, deleted_at: remove ? Time.current : nil, revision: message.revision + 1)
      Support::Audit.create!(account_id: @ticket.account_id, ticket_id: @ticket.id, actor: actor, action: remove ? 'message_removed' : 'message_edited', details: {message_uid: message.uid, previous_body: before})
      @ticket.update!(revision: @ticket.revision + 1)
      Support::Exchange.enqueue(@ticket, message: message)
    end
    kick_delivery
    redirect_to support_ticket_path(@ticket), notice: 'Mensagem atualizada.'
  rescue ActiveRecord::RecordInvalid
    redirect_to support_ticket_path(@ticket), alert: 'Não foi possível alterar a mensagem. Confira o conteúdo e se o chamado está aberto.'
  end

  def require_operator!
    head :forbidden unless support_operator?
  end
  def load_ticket = @ticket = visible_tickets.find(params[:id])
  def uploaded_files
    # Nunca aceitar signed IDs de blobs pertencentes a outra conta.
    Array(params[:files]).select { |file| file.is_a?(ActionDispatch::Http::UploadedFile) }.each do |file|
      type = Marcel::MimeType.for(file.tempfile)
      file.tempfile.rewind
      unless Support::Message::TYPES.include?(type) && file.size <= Support::Message::MAX_BYTES
        @ticket.errors.add(:base, "Use anexos JPG, PNG, WebP ou PDF de até 10 MB")
        raise ActiveRecord::RecordInvalid, @ticket
      end
      file.content_type = type
    end
  end
  def kick_delivery
    Support::DispatchJob.perform_later
  rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError
    # Outbox persistida: a recorrência retoma a entrega após indisponibilidade da fila.
    Rails.logger.warn("[support] entrega aguardando recorrência")
  end
  def related_errors
    # Correlação, não diagnóstico: apenas ocorrências recentes desta conta e deste usuário.
    ErrorEvent.where(tenant_id: current_tenant.id, source: 'request').where('last_seen_at >= ?', 15.minutes.ago)
      .where("context->>'admin_user_id' = ?", current_admin_user.id.to_s).order(last_seen_at: :desc).limit(5)
      .map { |error| { id: error.id, type: error.exception_class, seen_at: error.last_seen_at.iso8601 } }
  end

  def safe_source_path
    uri = URI.parse(request.referer.to_s)
    uri.host == request.host && uri.path.start_with?("/admin") ? uri.path.first(250) : nil
  rescue URI::InvalidURIError
    nil
  end
end
