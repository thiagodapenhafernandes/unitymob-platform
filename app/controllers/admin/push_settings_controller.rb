module Admin
  class PushSettingsController < Admin::BaseController
    before_action -> { check_permission!(:manage, :integracoes) }
    before_action :set_push_setting

    def edit
    end

    def update
      if @push_setting.update(push_setting_params)
        redirect_to edit_admin_push_setting_path, notice: "Configurações de push salvas com sucesso."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Gera um novo par de chaves VAPID personalizado (sobrepõe as do ambiente).
    def generate_keys
      unless @push_setting.encryption_ready?
        return redirect_to edit_admin_push_setting_path,
                           alert: "Criptografia indisponível: configure AR_ENCRYPTION_* antes de gerar as chaves VAPID."
      end

      @push_setting.generate_keys!
      redirect_to edit_admin_push_setting_path,
                  notice: "Novas chaves VAPID geradas. Dispositivos já inscritos precisarão reativar o push."
    rescue => e
      redirect_to edit_admin_push_setting_path, alert: "Falha ao gerar as chaves: #{e.message}"
    end

    # Descarta as chaves personalizadas e volta a usar as do ambiente (ENV).
    def use_env_keys
      @push_setting.use_env_keys!
      redirect_to edit_admin_push_setting_path,
                  notice: "Voltou a usar as chaves VAPID do ambiente (ENV)."
    rescue => e
      redirect_to edit_admin_push_setting_path, alert: "Falha ao restaurar as chaves do ambiente: #{e.message}"
    end

    private

    def set_push_setting
      @push_setting = PushSetting.instance
    end

    def push_setting_params
      params.require(:push_setting).permit(:enabled, :subject_email, :lead_click_action)
    end
  end
end
