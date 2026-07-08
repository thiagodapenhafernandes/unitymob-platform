module Admin
  class PushSettingsController < Admin::BaseController
    # VAPID/push é transporte GLOBAL: quem administra é o Admin do Sistema.
    # Tela removida dos perfis de conta (base_controller isenta este controller
    # do bounce de contexto de tenant para o system admin alcançá-la).
    before_action :require_system_admin!
    before_action :set_push_setting

    def edit
      load_push_health
    end

    def update
      if @push_setting.update(push_setting_params)
        redirect_to edit_admin_push_setting_path, notice: "Configurações de push salvas com sucesso."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Saúde do push por corretor (últimos 7 dias), a partir dos eventos de
    # entrega do dispatcher + confirmações de recepção do service worker.
    def load_push_health
      # System admin não tem tenant selecionado — a saúde por corretor é
      # per-tenant e só faz sentido dentro de uma conta (via impersonação).
      @push_health = []
      @push_health_summary = {}
      return if current_tenant.blank?

      window = 7.days.ago
      tenant_user_ids = current_tenant.admin_users.pluck(:id)

      events = PushDeliveryEvent.where(admin_user_id: tenant_user_ids)
                                .where("created_at >= ?", window)
                                .group(:admin_user_id, :event_type).count
      device_counts = PushSubscription.active.where(admin_user_id: tenant_user_ids).group(:admin_user_id).count
      last_received = PushDeliveryEvent.where(admin_user_id: tenant_user_ids, event_type: "device_received")
                                       .group(:admin_user_id).maximum(:created_at)

      active_ids = (events.keys.map(&:first) + device_counts.keys).uniq
      users = current_tenant.admin_users.where(id: active_ids).order(:name)

      @push_health = users.map do |user|
        sent = events[[user.id, "provider_accepted"]].to_i
        received = events[[user.id, "device_received"]].to_i
        failures = events[[user.id, "invalid_subscription"]].to_i +
                   events[[user.id, "provider_failed"]].to_i +
                   events[[user.id, "no_active_subscription"]].to_i
        devices = device_counts[user.id].to_i
        tone, label =
          if devices.zero? then [:gray, "Sem aparelho"]
          elsif sent.zero? then [:blue, "Sem envios"]
          elsif received.zero? then [:red, "Não confirma"]
          elsif received >= (sent * 0.7) then [:green, "Saudável"]
          else [:amber, "Instável"]
          end

        {
          user: user,
          devices: devices,
          sent: sent,
          received: received,
          failures: failures,
          last_received_at: last_received[user.id],
          tone: tone,
          label: label
        }
      end

      @push_health_summary = @push_health.group_by { |row| row[:tone] }.transform_values(&:count)
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
