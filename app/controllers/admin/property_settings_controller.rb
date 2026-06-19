module Admin
  class PropertySettingsController < BaseController
    before_action :require_admin!
    before_action :set_property_setting
    before_action :set_broker_capture_fallback_users, only: %i[edit review_workflow update]

    def edit
      @page_title = "Config Imóveis"
    end

    def update
      previous_layer_enabled = @property_setting.broker_capture_layer_enabled?
      @property_setting.watermark_image.purge if remove_watermark_image?
      @property_setting.assign_attributes(property_setting_params)
      return_to_review_workflow = params[:return_to].to_s == review_workflow_admin_property_setting_path

      if @property_setting.save
        if previous_layer_enabled && !@property_setting.broker_capture_layer_enabled
          reassign_broker_intakes_to_fallback_admin_user!
        end

        if return_to_review_workflow
          redirect_to review_workflow_admin_property_setting_path, notice: "Configurações de revisão atualizadas com sucesso."
        else
          redirect_to edit_admin_property_setting_path, notice: "Configurações de imóveis atualizadas com sucesso."
        end
      else
        if return_to_review_workflow
          @page_title = "Fluxo de revisão de captações"
          set_review_workflow_context
          render :review_workflow, status: :unprocessable_entity
        else
          @page_title = "Config Imóveis"
          render :edit, status: :unprocessable_entity
        end
      end
    end

    def review_workflow
      @page_title = "Fluxo de revisão de captações"
      set_review_workflow_context
    end

    def set_review_workflow_context
      @required_check_labels = @property_setting.active_broker_capture_checks.map do |key|
        PropertySetting::BROKER_INTAKE_CHECK_OPTIONS[key.to_s] || key
      end
      @returnable_section_labels = @property_setting.active_returnable_intake_edit_sections.map do |key|
        PropertySetting::RETURNABLE_INTAKE_EDIT_SECTION_OPTIONS[key.to_s] || key
      end
    end

    private

    def set_property_setting
      @property_setting = PropertySetting.instance
    end

    def property_setting_params
      params.require(:property_setting).permit(
        :watermark_position,
        :watermark_size_percentage,
        :watermark_opacity_percentage,
        :watermark_image,
        :broker_capture_layer_enabled,
        :broker_capture_fallback_admin_user_id,
        :notify_internal_review_events,
        :notify_email_review_events,
        :review_notification_emails,
        required_broker_intake_checks: [],
        returnable_intake_edit_sections: []
      )
    end

    def remove_watermark_image?
      ActiveModel::Type::Boolean.new.cast(params.dig(:property_setting, :remove_watermark_image))
    end

    def set_broker_capture_fallback_users
      administrative_profile = Profile.find_by(key: "administrativo")
      admin_users = AdminUser.where(role: :admin)
      @broker_capture_fallback_users = if administrative_profile
        admin_users.or(AdminUser.where(profile: administrative_profile)).order(:name).distinct
      else
        admin_users.order(:name)
      end
    end

    def reassign_broker_intakes_to_fallback_admin_user!
      return unless @property_setting.broker_capture_fallback_admin_user

      Habitation
        .reassignable_broker_intakes_for_capture_layer_deactivation
        .where.not(admin_user_id: @property_setting.broker_capture_fallback_admin_user_id)
        .update_all(admin_user_id: @property_setting.broker_capture_fallback_admin_user_id)
    end
  end
end
