class Admin::ChavesNaMaoConnectionsController < Admin::BaseController
  requires_permission :manage, :integracoes

  def update
    connection = ChavesNaMaoConnection.find_or_initialize_by(tenant: current_tenant)
    attrs = params.require(:chaves_na_mao_connection).permit(:account_code, :login_email, :integration_token, :enabled, :operational).to_h
    attrs.delete("integration_token") if attrs["integration_token"].blank?
    connection.assign_attributes(attrs)
    if connection.save
      redirect_to admin_portal_integrations_path(portal: "chavesnamao", anchor: "portal-direct-leads"),
        notice: "Configuração de recebimento direto salva. O envio de imóveis não foi alterado."
    else
      redirect_to admin_portal_integrations_path(portal: "chavesnamao", anchor: "portal-direct-leads"),
        alert: connection.errors.full_messages.to_sentence
    end
  end
end
