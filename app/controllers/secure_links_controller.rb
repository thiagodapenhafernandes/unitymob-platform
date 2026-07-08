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

  # Push: o clique vale como aceite do lead (dentro do prazo). Se o corretor
  # estiver logado no app (o push vai pro aparelho dele), abre o lead completo
  # no admin; senão, mostra o card seguro do lead.
  def handle_attend
    mark_attended!(via: "push")
    return render_lost_turn if link_no_longer_available?

    # Beacon: o service worker chamou em background só para registrar o aceite
    # (o clique já abriu o WhatsApp direto). Responde vazio, sem abrir tela.
    return head :no_content if params[:ack].present?

    return render :show, layout: false if params[:details].present?

    if current_admin_user
      redirect_to "/admin/leads/#{@lead.id}"
    else
      render :show, layout: false
    end
  end

  # O clique no contato é o "atendido": só efetiva se o lead ainda estiver
  # aguardando aceite (dentro do prazo do pocket), travando a redistribuição.
  # No Shark Tank (lead sem dono), reivindica para o corretor do link — 1º ganha.
  def mark_attended!(via:)
    return unless Lead.status_value(@lead.status) == Lead.status_value(:waiting_acceptance)

    if @lead.admin_user_id.nil?
      claimer = @link.issued_to_admin_user
      if claimer && Lead.claim!(@lead.id, claimer.id)
        @lead.reload
        @lead.distribution_rule&.mark_agent_served!(claimer.id)
        @lead.activities.create(
          kind: "accepted",
          metadata: { by: claimer.name, via: via, secure_link: true, shark_tank: true }.compact
        )
      else
        @lead.reload
      end
    else
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

  def noindex
    response.set_header("X-Robots-Tag", "noindex, nofollow, noarchive, nosnippet")
  end
end
