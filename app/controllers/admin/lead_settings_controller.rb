module Admin
  class LeadSettingsController < Admin::BaseController
    before_action -> { check_permission!(:manage, :distribution_rules) }
    before_action :set_lead_setting

    def edit
    end

    def update
      attrs = lead_setting_params
      # Janela em branco ou <= 0 significa "para sempre" (nil).
      if attrs[:stickiness_window_days].blank? || attrs[:stickiness_window_days].to_i <= 0
        attrs[:stickiness_window_days] = nil
      end

      if @lead_setting.update(attrs)
        redirect_to edit_admin_lead_setting_path, notice: "Configurações de leads salvas com sucesso."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_lead_setting
      @lead_setting = LeadSetting.instance
    end

    def lead_setting_params
      params.require(:lead_setting).permit(
        :stickiness_enabled,
        :stickiness_match,
        :stickiness_owner,
        :stickiness_fallback,
        :stickiness_window_days,
        :secure_links_enabled,
        :secure_link_expiry_days,
        :secure_link_whatsapp,
        :secure_link_email,
        :secure_link_push,
        :notify_on_distribution,
        :notify_on_sticky,
        :notify_on_redistribution,
        :notify_on_shark_tank,
        :notify_on_direct_assignment,
        :notify_on_reassignment,
        :notify_on_lost_turn
      )
    end
  end
end
