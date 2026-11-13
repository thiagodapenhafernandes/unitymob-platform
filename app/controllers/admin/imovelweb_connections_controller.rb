class Admin::ImovelwebConnectionsController < Admin::BaseController
  requires_permission :manage, :integracoes
  rescue_from ActiveRecord::RecordNotUnique, with: :duplicate_binding

  def create
    connection = connections.find_or_initialize_by(environment: 'production', advertiser_code: binding_params[:advertiser_code].to_s.strip)
    connection.client_code ||= "pending-#{SecureRandom.uuid}"
    save_binding(connection)
  end

  def update
    connection = connections.find(params[:id])
    connection.with_lock do
      return redirect_to(workspace_path, alert: 'O vínculo confirmado só pode ser alterado pelo suporte.') unless connection.binding_editable?
      connection.assign_attributes(binding_params)
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
    if connection.save(context: :binding_request)
      redirect_to workspace_path, notice: 'Dados do vínculo salvos. Autorização do portal pendente; produção não foi ativada.'
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
