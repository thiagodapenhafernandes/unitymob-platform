class Admin::ImovelwebConnectionsController < Admin::BaseController
  requires_permission :manage, :integracoes
  rescue_from ActiveRecord::RecordNotUnique, with: :duplicate_binding

  def authorization
    @connection = connections.find(params[:id])
    return head :not_found unless @connection.environment == "production"
    redirect_to "https://www.imovelweb.com.br/panel/empresa/integraciones-leads", allow_other_host: true
  end

  def challenge
    connection = connections.find(params[:id])
    return head :not_found unless connection.binding_editable?
    data = Imovelweb::GatewayClient.start_confirmation!(connection)
    connection.update!(binding_challenge_token: data.fetch("challenge_token"), binding_email_hint: data.fetch("email_hint"))
    redirect_to workspace_path, notice: "Código enviado ao e-mail administrativo cadastrado no Imovelweb."
  rescue Imovelweb::GatewayClient::Error => error
    redirect_to workspace_path, alert: error.message
  end

  def confirm
    connection = connections.find(params[:id])
    return head :not_found unless connection.binding_editable?
    code = params[:binding_code].to_s
    return redirect_to(workspace_path, alert: "Informe o código de seis dígitos.") unless code.match?(/\A[0-9]{6}\z/)
    proof = Imovelweb::GatewayClient.confirm!(connection, code: code)
    connection.update!(binding_proof: proof, authorization_requested_at: Time.current)
    connected = Imovelweb::ActivateConnection.call(connection)
    if connected
      ImovelwebListingSyncJob.perform_later(connection.id)
    else
      ImovelwebConnectionActivationJob.perform_later(connection.id)
    end
    redirect_to workspace_path, notice: connected ? "Vínculo confirmado. Os anúncios estão sendo preparados para receber contatos." : "Confirmação recebida. Aguardando a autorização no Imovelweb."
  rescue Imovelweb::GatewayClient::Error => error
    redirect_to workspace_path, alert: error.message
  end

  def verify
    connection = connections.find(params[:id])
    return head :not_found unless connection.environment == "production"
    connection.update!(authorization_requested_at: Time.current)
    connected = Imovelweb::ActivateConnection.call(connection)
    if connected
      ImovelwebListingSyncJob.perform_later(connection.id)
    else
      ImovelwebConnectionActivationJob.perform_later(connection.id)
    end
    notice = if connected
      "Recebimento de leads conectado ao Imovelweb."
    elsif connection.consent_confirmed_at.present?
      "Autorização encontrada. Confirme o vínculo pelo e-mail administrativo cadastrado no portal."
    else
      "Aguardando sua autorização no Imovelweb. A confirmação será automática nos próximos minutos."
    end
    redirect_to workspace_path, notice: notice
  rescue Imovelweb::GatewayClient::Error => error
    ImovelwebConnectionActivationJob.perform_later(connection.id) if connection
    redirect_to workspace_path, alert: error.message
  end

  def create
    connection = connections.find_or_initialize_by(environment: 'production', advertiser_code: binding_params[:advertiser_code].to_s.strip)
    connection.client_code ||= binding_params[:advertiser_code].to_s.strip
    save_binding(connection)
  end

  def update
    connection = connections.find(params[:id])
    connection.with_lock do
      return redirect_to(workspace_path, alert: 'O vínculo confirmado só pode ser alterado pelo suporte.') unless connection.binding_editable?
      connection.assign_attributes(binding_params)
      if connection.client_code.match?(/\A[0-9]+\z/) && connection.will_save_change_to_advertiser_code?
        return redirect_to(workspace_path, alert: 'Para outra sucursal, salve uma nova conexão. O vínculo atual foi preservado.')
      end
      save_binding(connection)
    end
  end

  private

  def connections
    ImovelwebConnection.where(tenant: current_tenant)
  end

  def binding_params
    params.require(:imovelweb_connection).permit(:advertiser_code)
  end

  def save_binding(connection)
    unless connection.binding_editable?
      return redirect_to workspace_path, alert: 'O vínculo confirmado só pode ser alterado pelo suporte.'
    end
    if connection.will_save_change_to_advertiser_code?
      connection.assign_attributes(consent_confirmed_at: nil, binding_email_hint: nil, binding_challenge_token: nil, binding_proof: nil)
    end
    connection.client_code = connection.advertiser_code if connection.new_record? || connection.client_code.match?(/\A(?:um|pending)-/)
    connection.authorization_requested_at = Time.current
    if connection.save(context: :binding_request)
      ImovelwebConnectionActivationJob.perform_later(connection.id)
      redirect_to workspace_path, notice: 'Conta salva. Autorize a Unitymob no Imovelweb para concluir a conexão automaticamente.'
    else
      redirect_to workspace_path, alert: connection.errors.full_messages.to_sentence
    end
  end

  def duplicate_binding
    redirect_to workspace_path, alert: 'Já existe uma solicitação com este código de conta.'
  end

  def workspace_path
    admin_portal_integrations_path(portal: 'imovelweb', anchor: 'portal-imovelweb-leads')
  end
end
