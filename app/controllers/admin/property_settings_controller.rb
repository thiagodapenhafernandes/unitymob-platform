module Admin
  class PropertySettingsController < BaseController
    before_action :require_admin!
    before_action :set_property_setting
    before_action :set_broker_capture_fallback_users, only: %i[edit review_workflow update update_review_workflow]
    before_action :set_ai_development_alias_context, only: %i[edit update]

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

    def update_review_workflow
      @page_title = "Fluxo de revisão de captações"
      set_review_context_params
      @review_policy = find_or_initialize_review_policy
      @review_policy.assign_attributes(review_policy_params)

      if @review_policy.save
        redirect_to review_workflow_admin_property_setting_path(review_context_query),
                    notice: "Regra de revisão salva para o conjunto selecionado."
      else
        set_review_workflow_context(policy: @review_policy)
        render :review_workflow, status: :unprocessable_entity
      end
    end

    def set_review_workflow_context(policy: nil)
      set_review_context_params
      @review_policy = policy || find_existing_review_policy
      @review_policy ||= build_review_policy_from_fallback
      @review_result = PropertyReviewPolicyResolver.call(
        tenant: current_tenant,
        property_setting: @property_setting,
        registration_type: @review_registration_type,
        category: @review_category,
        modality: @review_modality
      )
      @selected_rule = @review_result.policy || @property_setting
      @required_check_labels = @review_result.required_checks.map do |key|
        PropertySetting::BROKER_INTAKE_CHECK_OPTIONS[key.to_s] || key
      end
      @returnable_section_labels = @review_result.returnable_sections.map do |key|
        PropertySetting::RETURNABLE_INTAKE_EDIT_SECTION_OPTIONS[key.to_s] || key
      end
      @review_categories = categories_for_review_registration_type(@review_registration_type)
      @review_modalities = PropertyReviewPolicy::MODALITIES.to_a.map { |key, label| [label, key] }
      @review_registration_types = PropertyReviewPolicy::REGISTRATION_TYPES.to_a.map { |key, label| [label, key] }
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
        :ai_property_search_enabled,
        :voice_property_search_enabled,
        :ai_property_search_instructions,
        :ai_property_search_welcome_message,
        :ai_property_search_processing_message,
        :ai_property_search_no_results_message,
        :ai_property_search_data_source,
        :ai_property_search_max_results,
        :ai_property_search_default_sort,
        :ai_property_search_allow_flexible_results,
        :ai_property_search_price_tolerance_percentage,
        :ai_property_search_allow_clarifying_questions,
        :ai_property_search_require_filter_confirmation,
        :ai_property_search_max_audio_duration_seconds,
        :ai_property_search_language,
        :ai_property_search_history_enabled,
        :ai_property_search_history_retention_days,
        :ai_property_search_development_name_enabled,
        :ai_property_search_developer_name_enabled,
        :ai_property_search_fuzzy_matching_enabled,
        :ai_property_search_fuzzy_similarity_threshold,
        :ai_property_search_location_fuzzy_threshold,
        :ai_property_search_resilient_search_enabled,
        :ai_property_search_transcription_vocabulary_enabled,
        :ai_property_search_development_aliases_enabled,
        :ai_property_search_search_by_characteristics_enabled,
        :ai_property_search_catalog_property_types_limit,
        :ai_property_search_catalog_cities_limit,
        :ai_property_search_catalog_neighborhoods_limit,
        :ai_property_search_catalog_developments_limit,
        :ai_property_search_catalog_feature_terms_limit,
        :ai_property_search_catalog_alias_names_limit,
        :ai_property_search_sharing_enabled,
        :ai_property_search_share_max_properties,
        :ai_property_search_share_expiration_days,
        :ai_property_search_visitor_recognition_days,
        :ai_property_search_share_title,
        :ai_property_search_share_message,
        :ai_property_search_public_eyebrow,
        :ai_property_search_public_title,
        :ai_property_search_public_description,
        :ai_property_search_view_property_label,
        :ai_property_search_interest_button_label,
        :ai_property_search_identity_title,
        :ai_property_search_identity_description,
        :ai_property_search_identity_name_label,
        :ai_property_search_identity_phone_label,
        :ai_property_search_identity_submit_label,
        :ai_property_search_identity_cancel_label,
        :ai_property_search_interest_success_message,
        :ai_property_search_lead_origin,
        :ai_property_search_broker_panel_title,
        :ai_property_search_broker_event_message,
        :ai_property_search_selection_count_message,
        :ai_property_search_share_button_label,
        :ai_property_search_link_copied_message,
        :ai_property_search_share_error_message,
        :ai_property_search_interest_error_message,
        :ai_property_search_broker_event_meta,
        :ai_property_search_sharing_disabled_message,
        :ai_property_search_broker_events_limit,
        ai_property_search_allowed_fields: [],
        ai_property_search_result_fields: [],
        ai_property_search_allowed_profiles: [],
        required_broker_intake_checks: [],
        returnable_intake_edit_sections: []
      )
    end

    def review_policy_params
      params.require(:property_review_policy).permit(
        :broker_capture_layer_enabled,
        :notify_internal_review_events,
        :notify_email_review_events,
        :review_notification_emails,
        required_broker_intake_checks: [],
        returnable_intake_edit_sections: []
      )
    end

    def set_review_context_params
      @review_registration_type = params[:registration_type].presence_in(PropertyReviewPolicy::REGISTRATION_TYPES.keys) || "apartamentos"
      allowed_categories = categories_for_review_registration_type(@review_registration_type)
      @review_category = params[:category].presence_in(allowed_categories) || default_category_for_review_registration_type(@review_registration_type)
      @review_modality = params[:modality].presence_in(PropertyReviewPolicy::MODALITIES.keys) || "venda"
    end

    def review_context_query
      {
        registration_type: @review_registration_type,
        category: @review_category,
        modality: @review_modality
      }.compact
    end

    def find_existing_review_policy
      PropertyReviewPolicy.active.find_by(
        tenant: current_tenant,
        registration_type: @review_registration_type,
        category: @review_category,
        modality: @review_modality
      )
    end

    def find_or_initialize_review_policy
      find_existing_review_policy || build_review_policy_from_fallback
    end

    def build_review_policy_from_fallback
      current_tenant.property_review_policies.new(
        property_setting: @property_setting,
        registration_type: @review_registration_type,
        category: @review_category,
        modality: @review_modality,
        required_broker_intake_checks: @property_setting.active_broker_capture_checks,
        returnable_intake_edit_sections: @property_setting.active_returnable_intake_edit_sections,
        broker_capture_layer_enabled: @property_setting.broker_capture_layer_enabled,
        notify_internal_review_events: @property_setting.notify_internal_review_events,
        notify_email_review_events: @property_setting.notify_email_review_events,
        review_notification_emails: @property_setting.review_notification_emails
      )
    end

    def default_category_for_review_registration_type(registration_type)
      case registration_type
      when "terrenos" then "Terreno"
      when "comerciais_industriais" then "Sala Comercial"
      when "imoveis_residenciais" then "Casa"
      else "Apartamento"
      end
    end

    def categories_for_review_registration_type(registration_type)
      PropertyReviewPolicy::CATEGORIES_BY_REGISTRATION_TYPE.fetch(registration_type, Habitation::CATEGORIES)
    end

    def remove_watermark_image?
      ActiveModel::Type::Boolean.new.cast(params.dig(:property_setting, :remove_watermark_image))
    end

    def set_broker_capture_fallback_users
      @broker_capture_fallback_users = current_tenant.admin_users
        .active
        .includes(:profile, :horizontal_profile)
        .order(:name)
        .select { |user| user.tenant_owner? || (user.can?(:review, :captacoes) && user.owns_all?(:captacoes)) }
    end

    def set_ai_development_alias_context
      @ai_search_developments = current_tenant.habitations.where(tipo: "Empreendimento")
        .order(Arel.sql("COALESCE(nome_empreendimento, titulo_anuncio, codigo) ASC"))
        .limit(500)
      @development_aliases = DevelopmentAlias.where(tenant: current_tenant)
        .includes(:development).order(:normalized_name)
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
