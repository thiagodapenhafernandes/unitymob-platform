module Admin
  class LeadSettingsController < Admin::BaseController
    before_action -> { check_permission!(:manage, :distribution_rules) }
    before_action :set_lead_setting

    def edit
    end

    def update
      attrs = lead_setting_params
      push_click_action = attrs.delete(:push_lead_click_action)

      # Janela em branco ou <= 0 significa "para sempre" (nil).
      if attrs[:stickiness_window_days].blank? || attrs[:stickiness_window_days].to_i <= 0
        attrs[:stickiness_window_days] = nil
      end

      @lead_setting.assign_attributes(attrs)
      @lead_setting.push_lead_click_action = push_click_action if push_click_action.present?

      push_setting = PushSetting.instance
      push_setting.lead_click_action = push_click_action if push_click_action.present?

      lead_setting_valid = @lead_setting.valid?
      push_setting_valid = push_setting.valid?
      push_setting.errors.full_messages.each { |message| @lead_setting.errors.add(:base, "Push: #{message}") } unless push_setting_valid

      if lead_setting_valid && push_setting_valid
        ActiveRecord::Base.transaction do
          @lead_setting.save!
          push_setting.save! if push_click_action.present?
        end

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
        :push_lead_click_action,
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
