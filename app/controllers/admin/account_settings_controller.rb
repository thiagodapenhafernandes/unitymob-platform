# frozen_string_literal: true

# Hub "Configurações da Conta": página índice que agrega o que é da CONTA
# (marca, equipe/permissões, notificações, segurança, auditorias e compliance
# WhatsApp). Cada card respeita a permissão da tela de destino.
class Admin::AccountSettingsController < Admin::BaseController
  def show
    unless account_settings_visible?
      redirect_to admin_root_path, alert: "Você não tem acesso às configurações da conta."
    end
  end

  def update
    unless current_admin_user&.tenant_owner?
      return redirect_to admin_account_settings_path, alert: "Apenas o administrador da conta pode alterar os dados."
    end

    name = params.dig(:tenant, :name).to_s.strip
    if name.blank?
      redirect_to admin_account_settings_path, alert: "Informe o nome da conta."
    elsif current_tenant.update(name: name)
      redirect_to admin_account_settings_path, notice: "Dados da conta atualizados."
    else
      redirect_to admin_account_settings_path, alert: current_tenant.errors.full_messages.to_sentence
    end
  end

  private

  def account_settings_visible?
    current_admin_user&.tenant_owner? ||
      can?(:manage, :marketing) ||
      can?(:manage, :integracoes) ||
      can?(:manage, :access_security) ||
      can?(:view, :access_audit) ||
      can?(:view, :field_audit) ||
      can?(:view, :data_export_audit) ||
      can?(:view, :whatsapp_campaigns)
  end
end
