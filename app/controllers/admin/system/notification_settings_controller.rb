module Admin
  module System
    # Notificações Globais — Admin do Sistema (operador da aplicação).
    #
    # Edita os TRANSPORTES globais de notificação usados como fallback opt-in
    # pelas contas: WhatsApp global (SystemNotificationSetting), SMTP de fallback
    # (EmailSetting.global) e VAPID/Web Push (PushSetting.instance). Também
    # gerencia, por conta, os opt-ins use_global_whatsapp_fallback /
    # use_global_email_fallback.
    #
    # Gate igual ao de error_events: exclusivo do Admin do Sistema.
    class NotificationSettingsController < Admin::BaseController
      before_action :require_system_admin!
      before_action :load_settings, only: [:edit, :update]

      def edit
        load_tenant_fallbacks
      end

      def update
        ok = true

        if params[:system_notification_setting].present? && system_notification_supported?
          ok &&= @system_setting.update(system_notification_setting_params)
        end

        if params[:email_setting].present? && @global_email.present?
          email_attrs = email_setting_params
          email_attrs.delete(:smtp_password) if email_attrs[:smtp_password].blank?
          if @global_email.respond_to?(:encryption_ready?) && !@global_email.encryption_ready? && email_attrs[:smtp_password].present?
            flash.now[:alert] = "Criptografia indisponível: configure AR_ENCRYPTION_* antes de salvar a senha SMTP global."
            load_tenant_fallbacks
            return render :edit, status: :unprocessable_entity
          end
          ok &&= @global_email.update(email_attrs)
        end

        if params[:push_setting].present? && @push_setting.present?
          ok &&= @push_setting.update(push_setting_params)
        end

        if ok
          redirect_to edit_admin_system_notification_settings_path, notice: "Notificações globais salvas com sucesso."
        else
          load_tenant_fallbacks
          render :edit, status: :unprocessable_entity
        end
      end

      # Opt-in do fallback global por conta: liga/desliga, por Tenant, o uso dos
      # transportes globais quando a integração PRÓPRIA da conta não está pronta.
      def update_tenant_fallbacks
        unless tenant_fallback_columns_present?
          return redirect_to edit_admin_system_notification_settings_path,
                             alert: "As colunas de fallback por conta ainda não existem neste ambiente — rode as migrations pendentes."
        end

        wa_ids = Array(params[:use_global_whatsapp_fallback]).map(&:to_s)
        email_ids = Array(params[:use_global_email_fallback]).map(&:to_s)

        Tenant.find_each do |tenant|
          attrs = {}
          attrs[:use_global_whatsapp_fallback] = wa_ids.include?(tenant.id.to_s) if tenant.has_attribute?(:use_global_whatsapp_fallback)
          attrs[:use_global_email_fallback] = email_ids.include?(tenant.id.to_s) if tenant.has_attribute?(:use_global_email_fallback)
          tenant.update_columns(attrs) if attrs.any?
        end

        redirect_to edit_admin_system_notification_settings_path, notice: "Fallback global por conta atualizado."
      end

      private

      def load_settings
        @system_setting = SystemNotificationSetting.instance if system_notification_supported?
        @global_email = global_email_setting
        @push_setting = PushSetting.instance
      end

      def load_tenant_fallbacks
        @fallback_columns_ready = tenant_fallback_columns_present?
        @tenants = Tenant.order(:name).to_a
      end

      # A tabela/model é criada pela frente de migrations; até lá a seção some.
      def system_notification_supported?
        defined?(SystemNotificationSetting) && SystemNotificationSetting.respond_to?(:instance)
      rescue StandardError
        false
      end

      # EmailSetting.global é o registro global (tenant_id NULL). Antes da migration
      # de tenant_id o .global pode não existir — caímos no .instance (retrocompat).
      def global_email_setting
        if EmailSetting.respond_to?(:global)
          EmailSetting.global
        else
          EmailSetting.instance
        end
      rescue StandardError
        EmailSetting.instance
      end

      def tenant_fallback_columns_present?
        Tenant.column_names.include?("use_global_whatsapp_fallback") ||
          Tenant.column_names.include?("use_global_email_fallback")
      rescue StandardError
        false
      end

      def system_notification_setting_params
        attrs = params.require(:system_notification_setting).permit(
          :whatsapp_enabled,
          :whatsapp_access_token,
          :whatsapp_phone_number_id,
          :whatsapp_business_account_id,
          :whatsapp_template_name,
          :facebook_app_secret,
          :whatsapp_app_secret
        )

        attrs.delete(:whatsapp_access_token) if attrs[:whatsapp_access_token].blank?
        attrs.delete(:facebook_app_secret) if attrs[:facebook_app_secret].blank?
        attrs.delete(:whatsapp_app_secret) if attrs[:whatsapp_app_secret].blank?
        attrs
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

      def push_setting_params
        params.require(:push_setting).permit(:enabled, :subject_email, :lead_click_action)
      end
    end
  end
end
