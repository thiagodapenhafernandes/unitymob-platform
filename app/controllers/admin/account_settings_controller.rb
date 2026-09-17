# frozen_string_literal: true

# Hub "Configurações da Conta": página índice que agrega o que é da CONTA
# (marca, equipe/permissões, notificações, segurança, auditorias e compliance
# WhatsApp). Cada card respeita a permissão da tela de destino.
class Admin::AccountSettingsController < Admin::BaseController
  requires_permission :manage, :conta

  def show
  end

  def update
    unless can?(:manage, :conta)
      return redirect_to admin_account_settings_path, alert: "Você não tem permissão para alterar os dados da conta."
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
end
