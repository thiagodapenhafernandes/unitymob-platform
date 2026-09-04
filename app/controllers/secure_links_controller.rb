class SecureLinksController < ApplicationController
  before_action :noindex

  # GET /s/:token — o token é a credencial (link enviado ao corretor por WhatsApp).
  # Mantém o sistema como intermediário: o clique vira o evento de atendimento.
  def show
    @link = SecureLink.find_by(token: params[:token])

    unless @link&.valid_for_access?
      @reason = invalid_reason(@link)
      status = @reason == :not_found ? :not_found : :gone
      return render :invalid, status: status, layout: false
    end

    @link.record_access!
    @lead = @link.lead
    record_secure_link_access!
    return render_lost_turn if link_no_longer_available?

    return handle_contact_click(params[:contact]) if params[:contact].present?

    case @link.action_type
    when "phone" then handle_phone
    when "email" then handle_email
    when "attend" then handle_attend
    else handle_view
    end
  end

  private

  # Distingue os motivos do link não ser acessível para mostrar a mensagem certa:
  # inexistente (token errado ou lead recriado), expirado por prazo, ou desativado.
  def invalid_reason(link)
    return :not_found if link.nil?
    return :expired if link.expired?

    :inactive
  end

  def link_no_longer_available?
    return true if @secure_link_claim_failed

    issued_to = @link.issued_to_admin_user
    return false unless issued_to
    return false if @lead.admin_user_id.blank? && Lead.status_value(@lead.status) == Lead.status_value(:waiting_acceptance)

    @lead.admin_user_id.present? && @lead.admin_user_id != issued_to.id
  end

  def render_lost_turn
    return head :conflict if params[:ack].present?

    render :lost_turn, status: :ok, layout: false
  end

  def handle_phone
    mark_attended!(via: "whatsapp")
    return render_lost_turn if link_no_longer_available?

    url = @lead.direct_whatsapp_url
    return render :show, layout: false if url.blank?

    redirect_to url, allow_other_host: true
  end

  def handle_email
    mark_attended!(via: "email")
    return render_lost_turn if link_no_longer_available?

    email = @lead.display_email
    return render :show, layout: false if email.blank?

    redirect_to "mailto:#{email}", allow_other_host: true
  end

  def handle_view
    render :show, layout: false
  end

  def handle_contact_click(contact)
    case contact.to_s
    when "attend"
      mark_attended!(via: attendance_destination_via)
      return render_lost_turn if link_no_longer_available?

      redirect_to_attendance_destination
    when "whatsapp"
      mark_attended!(via: "whatsapp")
      return render_lost_turn if link_no_longer_available?

      url = @lead.direct_whatsapp_url
      return render :show, layout: false if url.blank?

      redirect_to url, allow_other_host: true
    when "email"
      mark_attended!(via: "email")
      return render_lost_turn if link_no_longer_available?

      email = @lead.display_email
      return render :show, layout: false if email.blank?

      redirect_to "mailto:#{email}", allow_other_host: true
    else
      render :show, layout: false
    end
  end

  def redirect_to_attendance_destination
    if open_whatsapp_from_secure_card?
      redirect_to @lead.direct_whatsapp_url, allow_other_host: true
    else
      redirect_to admin_lead_path(@lead)
    end
  end

  def attendance_destination_via
    open_whatsapp_from_secure_card? ? "whatsapp" : "system"
  end

  def open_whatsapp_from_secure_card?
    LeadSetting.instance(tenant: @lead.tenant).open_whatsapp_on_click? && @lead.direct_whatsapp_url.present?
  end

  # Push: quando configurado para "detalhes primeiro", o clique abre o card
  # seguro para o corretor decidir. O aceite fica no clique do contato. No
  # WhatsApp direto, o service worker envia ack=1 para marcar o aceite.
  def handle_attend
    return render_lost_turn if link_no_longer_available?

    if params[:details].present?
      return render :show, layout: false
    end

    mark_attended!(via: "push")
    return render_lost_turn if link_no_longer_available?

    # Beacon: o service worker chamou em background só para registrar o aceite
    # (o clique já abriu o WhatsApp direto). Responde vazio, sem abrir tela.
    return head :no_content if params[:ack].present?

    if current_admin_user
      redirect_to admin_lead_path(@lead)
    else
      render :show, layout: false
    end
  end

  # O clique no contato é o "atendido": só efetiva se o lead ainda estiver
  # aguardando aceite (dentro do prazo do pocket), travando a redistribuição.
  # No lead sem dono, reivindica para o corretor do link — 1º ganha.
  def mark_attended!(via:)
    if @lead.admin_user_id.nil?
      claimer = @link.issued_to_admin_user
      if claimer && claim_unassigned_lead!(claimer)
        @lead.reload
        @lead.distribution_rule&.mark_agent_served!(claimer.id)
        @lead.activities.create(
          kind: "accepted",
          metadata: { by: claimer.name, via: via, secure_link: true, shark_tank: true }.compact
        )
      else
        @lead.reload
        @secure_link_claim_failed = claimer.present? && @lead.admin_user_id.blank?
      end
    else
      return unless Lead.status_value(@lead.status) == Lead.status_value(:waiting_acceptance)

      owner_id = @lead.admin_user_id
      accepted = false
      # Transição atômica: revalida dono+status sob with_lock (mesma linha que
      # o PocketExpirationService trava) pra não sobrescrever um lead que
      # acabou de ser redistribuído a outro corretor.
      @lead.with_lock do
        accepted = @lead.admin_user_id == owner_id &&
          Lead.status_value(@lead.status) == Lead.status_value(:waiting_acceptance) &&
          @lead.update(status: Lead.status_value(:em_atendimento))
      end

      if accepted
        @lead.activities.create(
          kind: "accepted",
          metadata: { by: @lead.admin_user&.name, via: via, secure_link: true }.compact
        )
      end
      # Corrida perdida: @lead já foi recarregado pelo with_lock, então o
      # recheck link_no_longer_available? do caller renderiza lost_turn.
    end
  end

  def claim_unassigned_lead!(claimer)
    claimable_statuses = [
      Lead.status_value(:novo),
      Lead.status_value(:em_atendimento),
      Lead.status_value(:waiting_acceptance)
    ].compact

    Lead.where(id: @lead.id, admin_user_id: nil, status: claimable_statuses)
        .update_all(admin_user_id: claimer.id, status: Lead.status_value(:em_atendimento), updated_at: Time.current) == 1
  end

  def record_secure_link_access!
    issued_to = @link.issued_to_admin_user
    LeadActivity.log!(
      lead: @lead,
      kind: "secure_link_accessed",
      metadata: {
        by: issued_to&.name || current_admin_user&.name,
        admin_user_id: issued_to&.id || current_admin_user&.id,
        action_type: @link.action_type,
        contact: params[:contact].presence,
        via: secure_link_access_via,
        request_id: request.request_id,
        lead_status: @lead.status,
        lead_admin_user_id: @lead.admin_user_id
      }.compact
    )
  end

  def secure_link_access_via
    return "push_ack" if params[:ack].present?
    return "push" if params[:details].present? || @link.attend?
    return "email" if params[:contact].to_s == "email" || @link.email?
    return "whatsapp" if params[:contact].to_s.in?(%w[attend whatsapp]) || @link.phone?

    "secure_link"
  end

  def noindex
    response.set_header("X-Robots-Tag", "noindex, nofollow, noarchive, nosnippet")
  end
end
