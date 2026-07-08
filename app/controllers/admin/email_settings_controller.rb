module Admin
  class EmailSettingsController < Admin::BaseController
    before_action -> { check_permission!(:manage, :integracoes) }
    before_action :set_email_setting
    before_action :set_effective_email_transport

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
      unless @effective_email_setting&.configured?
        return redirect_to edit_admin_email_setting_path, alert: "Ative e configure o SMTP próprio ou libere o SMTP global para enviar um teste."
      end

      to = params[:to].presence || @effective_email_setting.from_email
      SettingsMailer.with(setting: @effective_email_setting, to: to).smtp_test.deliver_now
      record_smtp_test_result(ok: true, to: to)
      redirect_to edit_admin_email_setting_path, notice: "E-mail de teste enviado para #{to}."
    rescue => e
      record_smtp_test_result(ok: false, to: params[:to].presence || @email_setting.from_email, error: e.message)
      redirect_to edit_admin_email_setting_path, alert: "Falha ao enviar o teste: #{e.message}"
    end

    private

    # Resultado do último teste fica PERSISTIDO no painel (o toast some em
    # segundos e o usuário fica sem saber se funcionou).
    def record_smtp_test_result(ok:, to:, error: nil)
      Setting.set(
        "email_smtp_last_test",
        { ok: ok, to: to, error: error.to_s.first(200).presence, at: Time.current.iso8601 }.to_json,
        "Resultado do último teste de SMTP"
      )
    rescue => e
      Rails.logger.warn "[EmailSettings] não registrou resultado do teste: #{e.message}"
    end

    # A tela do DONO DA CONTA edita o SMTP PRÓPRIO do tenant — não o global.
    # A edição do SMTP global de fallback migrou para o Admin do Sistema
    # (Admin::System::NotificationSettingsController).
    #
    # Tolerante pré-migration: enquanto a coluna tenant_id não existe, cai para
    # o registro singleton (.instance) para não quebrar a tela.
    def set_email_setting
      @email_setting =
        if tenant_scoped_email_settings? && current_tenant.present?
          EmailSetting.find_or_initialize_by(tenant: current_tenant)
        else
          EmailSetting.instance
        end
    end

    def tenant_scoped_email_settings?
      EmailSetting.column_names.include?("tenant_id")
    rescue StandardError
      false
    end

    def set_effective_email_transport
      @email_transport = Notifications::TransportResolver.email(current_tenant)
      @email_transport_source = @email_transport&.source
      @effective_email_setting = @email_transport&.sender
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
