class Admin::ChavesNaMaoConnectionsController < Admin::BaseController
  requires_permission :manage, :integracoes

  def update
    connection = ChavesNaMaoConnection.find_or_initialize_by(tenant: current_tenant)
    attrs = params.require(:chaves_na_mao_connection).permit(:account_code, :integration_token, :enabled).to_h
    attrs.delete("integration_token") if attrs["integration_token"].blank?
    connection.assign_attributes(attrs)
    if connection.save
      redirect_to admin_portal_integrations_path(portal: "chavesnamao", anchor: "portal-direct-leads"),
        notice: "Configuração de validação salva. O C2S e o envio de imóveis não foram alterados."
    else
      redirect_to admin_portal_integrations_path(portal: "chavesnamao", anchor: "portal-direct-leads"),
        alert: connection.errors.full_messages.to_sentence
    end
  end
end
