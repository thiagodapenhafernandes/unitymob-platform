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

  def handle_phone
    mark_attended!(via: "whatsapp")
    url = @lead.direct_whatsapp_url
    return render :show, layout: false if url.blank?

    redirect_to url, allow_other_host: true
  end

  def handle_email
    mark_attended!(via: "email")
    email = @lead.display_email
    return render :show, layout: false if email.blank?

    redirect_to "mailto:#{email}", allow_other_host: true
  end

  def handle_view
    render :show, layout: false
  end

  # Push: o clique vale como aceite do lead (dentro do prazo). Se o corretor
  # estiver logado no app (o push vai pro aparelho dele), abre o lead completo
  # no admin; senão, mostra o card seguro do lead.
  def handle_attend
    mark_attended!(via: "push")

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
        @lead.reload.activities.create(
          kind: "accepted",
          metadata: { by: claimer.name, via: via, secure_link: true, shark_tank: true }.compact
        )
      end
    else
      @lead.update(status: Lead.status_value(:em_atendimento))
      @lead.activities.create(
        kind: "accepted",
        metadata: { by: @lead.admin_user&.name, via: via, secure_link: true }.compact
      )
    end
  end

  def noindex
    response.set_header("X-Robots-Tag", "noindex, nofollow, noarchive, nosnippet")
  end
end
