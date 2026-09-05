require "base64"
require "stringio"

class Support::Exchange
  TICKET_FIELDS = %w[origin outreach_kind requester_email uid requester_id requester_name subject intake diagnostics source_path status priority labels assignee_name previous_uid revision first_response_at resolved_at created_at updated_at].freeze
  class Conflict < StandardError; end

  def self.enqueue(ticket, message: nil, command: nil)
    payload = { "kind" => command || "snapshot", "ticket" => ticket.attributes.slice(*TICKET_FIELDS), "message_uid" => message&.uid }
    Support::Delivery.create!(account: ticket.account, ticket: ticket, payload: payload)
  end

  def self.wire(delivery)
    payload = delivery.payload.merge("event_id" => delivery.uid)
    if (uid = payload.delete("message_uid"))
      message = delivery.ticket.messages.find_by!(uid: uid, internal: false)
      payload["message"] = message.attributes.slice("uid", "side", "author", "body", "created_at", "author_staff_id", "edited_at", "deleted_at", "revision").merge("files" => message.files.map do |file|
        { "filename" => file.filename.to_s, "type" => file.content_type, "data" => Base64.strict_encode64(file.download) }
      end)
    end
    payload
  end

  def self.receive(account, payload)
    raise ArgumentError, "Evento inválido" unless payload.is_a?(Hash)
    raise ArgumentError, "Evento inválido" unless payload["event_id"].to_s.match?(/\A[0-9a-f-]{36}\z/)
    account.with_lock do
      return if Support::Receipt.exists?(account_id: account.id, uid: payload["event_id"])
      case payload["kind"]
      when "account_state", "revoke_access"
        raise ArgumentError, "Direção inválida" if SupportDesk.central?
        if payload["kind"] == "account_state"
          return if payload.fetch("revision").to_i <= account.control_revision
          account.update!(active: payload.fetch("active"), control_revision: payload.fetch("revision"))
        end
        sessions = Support::AccessSession.where(account_id: account.id, ended_at: nil)
        if payload["kind"] == "revoke_access"
          sessions = sessions.where(operator_id: payload.fetch("operator_id")).where("created_at <= ?", Time.iso8601(payload.fetch("issued_at")))
        end
        sessions.update_all(ended_at: Time.current) if payload["kind"] == "revoke_access" || !account.active?
      when "access_audit"
        raise ArgumentError, "Direção inválida" unless SupportDesk.central?
        ticket = account.tickets.find_by!(uid: payload.fetch("ticket_uid"))
        data = payload.fetch("audit")
        Support::Audit.create!(account_id: account.id, ticket_id: ticket.id, actor: data.fetch("actor"), action: data.fetch("action"), details: data.fetch("details", {}))
      else
        SupportDesk.central? ? command(account, payload) : snapshot(account, payload)
      end
      Support::Receipt.create!(account_id: account.id, uid: payload.fetch("event_id"))
    end
  end

  def self.command(account, payload)
    raise ArgumentError, "Chamado inválido" unless payload["ticket"].is_a?(Hash)
    attrs = payload.fetch("ticket").slice(*TICKET_FIELDS)
    raise ArgumentError, "Comando inválido" unless %w[create message].include?(payload["kind"])
    ticket = account.tickets.find_by(uid: attrs.fetch("uid"))
    if payload["kind"] == "create" && ticket.nil?
      ticket = account.tickets.create!(attrs.slice("uid", "requester_id", "requester_name", "requester_email", "subject", "intake", "diagnostics", "source_path", "previous_uid"))
    end
    Support::Timeline.record!(ticket, "received") if ticket&.previously_new_record?
    raise Conflict, "Chamado indisponível ou resolvido" unless ticket && !ticket.resolved?
    raise ArgumentError, "Solicitante inválido" unless ticket.requester_id == attrs.fetch("requester_id")
    raise ArgumentError, "Mensagem inválida" unless payload["message"].is_a?(Hash)
    message_data = payload.fetch("message").merge("side" => "requester", "author" => ticket.requester_name, "author_staff_id" => nil, "edited_at" => nil, "deleted_at" => nil, "revision" => 0)
    message = append_message(ticket, message_data)
    ticket.update!(status: ticket.status == "aguardando_usuario" ? "em_atendimento" : ticket.status, revision: ticket.revision + 1, updated_at: Time.current)
    Support::Timeline.record!(ticket, "requester_message") if message.previously_new_record?
    enqueue(ticket, message: message)
  end

  def self.snapshot(account, payload)
    raise ArgumentError, "Evento inválido" unless %w[snapshot outreach].include?(payload["kind"])
    raise ArgumentError, "Chamado inválido" unless payload["ticket"].is_a?(Hash)
    attrs = payload.fetch("ticket").slice(*TICKET_FIELDS)
    ticket = account.tickets.find_by(uid: attrs.fetch("uid"))
    if ticket.nil? && payload['kind'] == 'outreach'
      user = AdminUser.find_by!(id: attrs.fetch('requester_id'), tenant_id: account.local_tenant_id, active: true)
      raise ArgumentError, 'Destinatário inválido' if user.system_admin?
      ticket = account.tickets.create!(attrs.except('revision').merge('origin'=>'ativo', 'requester_name'=>user.name, 'requester_email'=>user.email))
    end
    raise ActiveRecord::RecordNotFound unless ticket
    message = append_message(ticket, payload["message"], projection: true) if payload["message"]
    if attrs.fetch("revision").to_i > ticket.revision
      # Projeção recebe estado validado pela central, sem reabrir chamados locais por eventos antigos.
      ticket.update_columns(attrs.except("uid", "created_at"))
    end
    if message&.previously_new_record? && message.side == "support"
      message.update_columns(notification_pending: true)
    end
  end

  def self.append_message(ticket, data, projection: false)
    raise ArgumentError, "Mensagem inválida" unless data.is_a?(Hash) && data["uid"].is_a?(String) && data.fetch("files", []).is_a?(Array)
    existing = ticket.messages.find_by(uid: data.fetch("uid"))
    if existing
      if projection && data.fetch('revision', 0).to_i > existing.revision
        raise ArgumentError, 'Mensagem inválida' unless data['body'].is_a?(String) && data['body'].length <= 20_000
        existing.update_columns(data.slice('body', 'edited_at', 'deleted_at', 'revision'))
      end
      return existing
    end
    raise ArgumentError, "Mensagem inválida" unless data.fetch("uid").match?(/\A[0-9a-f-]{36}\z/)
    files = data.fetch("files", [])
    raise ArgumentError, "Muitos anexos" if files.size > 5
    message = ticket.messages.build(data.slice("uid", "side", "author", "body", "created_at", "author_staff_id", "edited_at", "deleted_at", "revision"))
    files.each do |file|
      raise ArgumentError, "Anexo muito grande" if file.fetch("data").bytesize > 14.megabytes
      bytes = Base64.strict_decode64(file.fetch("data"))
      type = Marcel::MimeType.for(StringIO.new(bytes))
      raise ArgumentError, "Anexo inválido" unless Support::Message::TYPES.include?(type) && bytes.bytesize <= Support::Message::MAX_BYTES
      message.files.attach(io: StringIO.new(bytes), filename: File.basename(file.fetch("filename")), content_type: type)
    end
    # Mensagens históricas podem chegar após o evento de resolução.
    if projection
      raise ArgumentError, "Mensagem inválida" unless %w[requester support].include?(message.side) && message.author.present? && (message.body.present? || files.any?) && message.body.to_s.length <= 20_000
      message.save!(validate: false)
    else
      message.save!
    end
    message
  end
end
