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
      review_policy_before = PropertyReviewPolicy::ChangeRecorder.snapshot(@property_setting)
      review_policy_impact = PropertyReviewPolicy::ImpactReport.call(tenant: current_tenant, setting: @property_setting)
      @property_setting.watermark_image.purge if remove_watermark_image?
      @property_setting.assign_attributes(property_setting_params)
      return_to_review_workflow = params[:return_to].to_s == review_workflow_admin_property_setting_path
      proposal = PropertyReviewPolicy::ProposalReport.call(before_snapshot: review_policy_before, proposed_setting: @property_setting, impact_snapshot: review_policy_impact)

      if simulate_review_policy?
        @review_policy_proposal = proposal
        @page_title = "Fluxo de revisão de captações"
        set_review_workflow_context
        render :review_workflow
        return
      end

      if proposal["requires_operational_confirmation"] && @property_setting.valid? && !operational_impact_confirmed?
        @property_setting.errors.add(:base, "Confirme a reatribuição das captações em andamento antes de desligar a revisão administrativa.")
        @review_policy_proposal = proposal
        @requires_operational_confirmation = true
        @page_title = "Fluxo de revisão de captações"
        set_review_workflow_context
        render :review_workflow, status: :unprocessable_entity
        return
      end

      saved = false
      PropertySetting.transaction do
        saved = @property_setting.save
        raise ActiveRecord::Rollback unless saved

        PropertyReviewPolicy::ChangeRecorder.call(setting: @property_setting, admin_user: current_admin_user, before_snapshot: review_policy_before, impact_snapshot: review_policy_impact)
        if previous_layer_enabled && !@property_setting.broker_capture_layer_enabled
          reassign_broker_intakes_to_fallback_admin_user!
        end
      end

      if saved
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
      @review_policy_impact = PropertyReviewPolicy::ImpactReport.call(tenant: current_tenant, setting: @property_setting)
      @review_policy_audits = @property_setting.review_policy_audit_logs.includes(:admin_user).recent.limit(10)
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

    def simulate_review_policy?
      ActiveModel::Type::Boolean.new.cast(params[:simulate_review_policy])
    end

    def operational_impact_confirmed?
      ActiveModel::Type::Boolean.new.cast(params[:confirm_operational_impact])
    end

    def set_broker_capture_fallback_users
      @broker_capture_fallback_users = current_tenant.admin_users
        .active
        .includes(:profile, :horizontal_profile)
        .order(:name)
        .select { |user| user.tenant_owner? || (user.can?(:review, :captacoes) && user.owns_all?(:captacoes)) }
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
