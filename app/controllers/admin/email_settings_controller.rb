module Admin
  class EmailSettingsController < Admin::BaseController
    before_action -> { check_permission!(:manage, :integracoes) }
    before_action :set_email_setting

    def edit
    end

    def update
      attributes = email_setting_params
      # Não sobrescreve a senha guardada quando o campo é enviado em branco.
      attributes.delete(:smtp_password) if attributes[:smtp_password].blank?

      if !@email_setting.encryption_ready? && attributes[:smtp_password].present?
        flash.now[:alert] = "Criptografia indisponível: configure AR_ENCRYPTION_* antes de salvar a senha SMTP."
        return render :edit, status: :unprocessable_entity
      end

      if @email_setting.update(attributes)
        redirect_to edit_admin_email_setting_path, notice: "Configurações de e-mail salvas com sucesso."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Envia um e-mail de teste para validar as credenciais SMTP.
    def test
      unless @email_setting.configured?
        return redirect_to edit_admin_email_setting_path, alert: "Ative e configure o SMTP antes de enviar um teste."
      end

      to = params[:to].presence || @email_setting.from_email
      SettingsMailer.with(setting: @email_setting, to: to).smtp_test.deliver_now
      redirect_to edit_admin_email_setting_path, notice: "E-mail de teste enviado para #{to}."
    rescue => e
      redirect_to edit_admin_email_setting_path, alert: "Falha ao enviar o teste: #{e.message}"
    end

    private

    def set_email_setting
      @email_setting = EmailSetting.instance
    end

    def email_setting_params
      params.require(:email_setting).permit(
        :enabled,
        :smtp_address, :smtp_port, :smtp_domain,
        :smtp_user_name, :smtp_password,
        :smtp_authentication, :smtp_enable_starttls_auto,
        :from_name, :from_email, :reply_to
      )
    end
  end
end
