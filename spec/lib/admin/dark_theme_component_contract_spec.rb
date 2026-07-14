require "spec_helper"

RSpec.describe "Contrato dark dos componentes compartilhados do admin" do
  COMPONENT_ROOT_SELECTORS = {
    "admin_user_form" => "au-form",
    "alert" => "ax-alert",
    "appointment_card" => "ax-appointment-card",
    "aside_panel" => "ax-aside-panel-shell",
    "audience_workspace" => "ax-audience-workspace",
    "avatar" => "ax-avatar",
    "audit_history_modal" => "ax-tl-card",
    "badge" => "ax-badge",
    "board" => "ax-board",
    "button" => "ax-btn",
    "card" => "ax-card",
    "clearable_control" => "ax-clearable-control",
    "color_field" => "ax-color-field",
    "code_snippet" => "ax-code-snippet",
    "confirm_submit" => "ax-confirm-submit",
    "contextbar_button" => "ax-contextbar__button",
    "disclosure_card" => "ax-disclosure-card",
    "dismissible_hint" => "ax-dismissible-hint",
    "drawer" => "ax-drawer-backdrop",
    "empty_state" => "ax-empty-state",
    "field_feedback" => "ax-field",
    "field_grid" => "ax-field-grid",
    "field_group" => "ax-field-group",
    "field_label" => "ax-field-label",
    "file_list" => "ax-file-list",
    "filter_form" => "ax-filter-form",
    "filter_section" => "ax-filter-section",
    "form_actions" => "ax-form-actions",
    "form_control" => "ax-control",
    "form_section" => "ax-form-section",
    "form_tabs" => "ax-form-tabs",
    "icon_button" => "ax-ico-btn",
    "inline_notice" => "ax-inline-notice",
    "input_group" => "ax-input-group",
    "lead_label_chip" => "lead-label-chip",
    "loading" => "ax-spinner",
    "media_modal" => "ax-media-modal",
    "media_preview" => "ax-media-preview",
    "menu" => "ax-menu",
    "metric_card" => "ax-metric-grid",
    "modal" => "ax-modal-overlay",
    "module_objective" => "ax-module-objective",
    "operational_panel" => "ax-operational-panel",
    "option_card" => "ax-option-card__input",
    "panel" => "ax-panel",
    "page_heading" => "ax-page-title",
    "pagination" => "ax-pagination",
    "progress" => "ax-progress",
    "presentation_cards" => "pc-manager",
    "quick_modal" => "ax-quick-modal",
    "radio_group" => "ax-radio-group",
    "record_item" => "ax-record-item",
    "search" => "ax-search",
    "stack" => "ax-option-stack",
    "status_list" => "ax-status-list",
    "sticky_action_footer" => "ax-sticky-action-footer",
    "switch" => "ax-check",
    "system_workspace" => "ax-system",
    "table" => "ax-table-wrap",
    "team_toggle" => "ax-team-toggle",
    "toggle_chip" => "ax-toggle-group",
    "tooltip" => "ax-tooltip",
    "upload" => "ax-file-upload__input",
    "view_toggle" => "ax-view-toggle",
    "whatsapp_campaign_builder" => "whatsapp-campaign-builder",
    "whatsapp_integration" => "wa-workspace",
    "workflow" => "ax-workflow",
    "workspace_heading" => "ax-workspace-heading",
    "workspace_shell" => "ax-workspace-shell"
  }.freeze

  THEME_NEUTRAL_COMPONENTS = %w[code_snippet field_grid stack].freeze

  subject(:stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin_tailwind.css", __dir__))
  end

  let(:dark_theme_progress_report) do
    File.read(File.expand_path("../../../docs/admin_dark_theme_progress.md", __dir__))
  end

  let(:shared_component_paths) do
    Dir[File.expand_path("../../../app/assets/stylesheets/admin/components/*.css", __dir__)].sort
  end

  let(:admin_dark_contract_paths) do
    stylesheets_root = File.expand_path("../../../app/assets/stylesheets", __dir__)

    (
      Dir[File.join(stylesheets_root, "admin*.css")] +
      Dir[File.join(stylesheets_root, "admin/**/*.css")]
    ).uniq.sort.reject do |path|
      path.end_with?("/admin_compat.css", "/admin/theme_tokens.css")
    end
  end

  def admin_stylesheet_label(path)
    path.sub(%r{\A.*?/app/assets/stylesheets/}, "")
  end

  def custom_property_value(source, property)
    source[/#{Regexp.escape(property)}\s*:\s*([^;]+);/, 1]&.strip
  end

  let(:view_toggle_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/view_toggle.css", __dir__))
  end

  let(:avatar_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/avatar.css", __dir__))
  end

  let(:avatar_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_avatar.html.erb", __dir__))
  end

  let(:avatar_consumer_views) do
    %w[
      admin_users/index.html.erb
      admin_users/show.html.erb
      admin_users/_hierarchy_node.html.erb
      presentation_cards/_profile_preview.html.erb
      presentation_cards/_quick_edit_modal.html.erb
    ].map { |path| File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__)) }
  end

  let(:appointment_card_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/appointment_card.css", __dir__))
  end

  let(:admin_user_form_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/admin_user_form.css", __dir__))
  end

  let(:admin_user_form_view) do
    File.read(File.expand_path("../../../app/views/admin/admin_users/_form.html.erb", __dir__))
  end

  let(:admin_user_support_views) do
    %w[
      admin_users/_vista_sync_panel.html.erb
      admin_users/_backfill_brokers_panel.html.erb
      admin_users/_hierarchy_node.html.erb
      system/users.html.erb
    ].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:appointment_card_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_appointment_card.html.erb", __dir__))
  end

  let(:appointments_index_view) do
    File.read(File.expand_path("../../../app/views/admin/appointments/index.html.erb", __dir__))
  end

  let(:dismissible_hint_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/dismissible_hint.css", __dir__))
  end

  let(:dismissible_hint_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_dismissible_hint.html.erb", __dir__))
  end

  let(:dismissible_controller) do
    File.read(File.expand_path("../../../app/javascript/controllers/dismissible_controller.js", __dir__))
  end

  let(:dismissible_hint_consumers) do
    %w[appointments tasks automation_rules].map do |directory|
      File.read(File.expand_path("../../../app/views/admin/#{directory}/index.html.erb", __dir__))
    end
  end

  let(:badge_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/badge.css", __dir__))
  end

  let(:alert_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/alert.css", __dir__))
  end

  let(:switch_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/switch.css", __dir__))
  end

  let(:switch_field_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_switch_field.html.erb", __dir__))
  end

  let(:toggle_chip_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/toggle_chip.css", __dir__))
  end

  let(:toggle_chip_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_toggle_chip.html.erb", __dir__))
  end

  let(:checkbox_chips_controller) do
    File.read(File.expand_path("../../../app/javascript/controllers/ax_checkbox_chips_controller.js", __dir__))
  end

  let(:radio_group_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/radio_group.css", __dir__))
  end

  let(:radio_group_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_radio_group.html.erb", __dir__))
  end

  let(:upload_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/upload.css", __dir__))
  end

  let(:progress_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/progress.css", __dir__))
  end

  let(:file_field_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_file_field.html.erb", __dir__))
  end

  let(:file_upload_button_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_file_upload_button.html.erb", __dir__))
  end

  let(:attachment_item_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_attachment_item.html.erb", __dir__))
  end

  let(:progress_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_progress.html.erb", __dir__))
  end

  let(:file_list_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/file_list.css", __dir__))
  end

  let(:empty_state_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/empty_state.css", __dir__))
  end

  let(:empty_state_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_empty_state.html.erb", __dir__))
  end

  let(:compact_empty_state_views) do
    %w[
      banners/index.html.erb
      data_export_audit_logs/index.html.erb
      home_sections/index.html.erb
      marketing_properties/index.html.erb
      proprietors/index.html.erb
      attribute_options/index.html.erb
    ].map { |path| File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__)) }
  end

  let(:metric_card_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/metric_card.css", __dir__))
  end

  let(:metric_card_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_metric_card.html.erb", __dir__))
  end

  let(:inline_notice_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/inline_notice.css", __dir__))
  end

  let(:inline_notice_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_inline_notice.html.erb", __dir__))
  end

  let(:admin_ui_helper_source) do
    File.read(File.expand_path("../../../app/helpers/admin/ui_helper.rb", __dir__))
  end

  let(:inline_notice_consumer_views) do
    %w[
      whatsapp_campaigns/_form.html.erb
      whatsapp_campaigns/show.html.erb
      automation_workflows/new.html.erb
    ].map { |path| File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__)) }
  end

  let(:record_item_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/record_item.css", __dir__))
  end

  let(:quick_modal_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/quick_modal.css", __dir__))
  end

  let(:audit_history_modal_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/audit_history_modal.css", __dir__))
  end

  let(:audit_history_modal_view) do
    File.read(File.expand_path("../../../app/views/admin/habitations/_audit_history_modal.html.erb", __dir__))
  end

  let(:clearable_control_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/clearable_control.css", __dir__))
  end

  let(:clear_field_controller) do
    File.read(File.expand_path("../../../app/javascript/controllers/ax_clear_field_controller.js", __dir__))
  end

  let(:clearable_field_views) do
    %w[_text_field.html.erb _select_field.html.erb _number_field.html.erb _date_field.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/shared/ui/#{path}", __dir__))
    end
  end

  let(:input_group_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/input_group.css", __dir__))
  end

  let(:field_label_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/field_label.css", __dir__))
  end

  let(:field_label_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_field_label.html.erb", __dir__))
  end

  let(:field_feedback_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/field_feedback.css", __dir__))
  end

  let(:validation_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/ax_toast.css", __dir__))
  end

  let(:field_group_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/field_group.css", __dir__))
  end

  let(:filter_form_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/filter_form.css", __dir__))
  end

  let(:filter_form_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_filter_form.html.erb", __dir__))
  end

  let(:whatsapp_inbox_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/whatsapp_inbox_refresh.css", __dir__))
  end

  let(:whatsapp_composer_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_whatsapp_composer.html.erb", __dir__))
  end

  let(:admin_sidebar_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/_sidebar.html.erb", __dir__))
  end

  let(:property_catalog_actions_view) do
    File.read(File.expand_path("../../../app/views/admin/habitations/_property_catalog_actions.html.erb", __dir__))
  end

  let(:whatsapp_campaign_unsubscribes_view) do
    File.read(File.expand_path("../../../app/views/admin/whatsapp_campaign_unsubscribes/index.html.erb", __dir__))
  end

  let(:whatsapp_campaign_recipients_view) do
    File.read(File.expand_path("../../../app/views/admin/whatsapp_campaign_recipients/index.html.erb", __dir__))
  end

  let(:banner_views) do
    %w[banners/_form.html.erb banners/show.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:banners_index_view) do
    File.read(File.expand_path("../../../app/views/admin/banners/index.html.erb", __dir__))
  end

  let(:leads_index_view) do
    File.read(File.expand_path("../../../app/views/admin/leads/index.html.erb", __dir__))
  end

  let(:captacoes_metric_views) do
    %w[captacoes/index.html.erb captacoes/dashboard.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:captacoes_index_view) do
    File.read(File.expand_path("../../../app/views/admin/captacoes/index.html.erb", __dir__))
  end

  let(:captacoes_dashboard_view) do
    File.read(File.expand_path("../../../app/views/admin/captacoes/dashboard.html.erb", __dir__))
  end

  let(:tracking_integrations_view) do
    File.read(File.expand_path("../../../app/views/admin/tracking_integrations/show.html.erb", __dir__))
  end

  let(:captacao_review_views) do
    %w[captacoes/show.html.erb captacoes/steps/_review.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:captacao_wizard_views) do
    %w[
      captacoes/new.html.erb captacoes/edit.html.erb captacoes/steps/_intro.html.erb
      captacoes/steps/_proprietario.html.erb captacoes/steps/_endereco.html.erb
      captacoes/steps/_caracteristicas.html.erb captacoes/steps/_infraestrutura.html.erb
      captacoes/steps/_negociacao.html.erb captacoes/steps/_visitas.html.erb
      captacoes/steps/_fotos.html.erb
    ].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:captacao_wizard_layout) do
    File.read(File.expand_path("../../../app/views/layouts/captacao_wizard.html.erb", __dir__))
  end

  let(:captacao_wizard_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/captacao_wizard.css", __dir__))
  end

  let(:captacoes_ranking_table_view) do
    File.read(File.expand_path("../../../app/views/admin/captacoes/_ranking_table.html.erb", __dir__))
  end

  let(:captacoes_leads_heatmap_view) do
    File.read(File.expand_path("../../../app/views/admin/captacoes/_leads_heatmap.html.erb", __dir__))
  end

  let(:home_settings_edit_view) do
    File.read(File.expand_path("../../../app/views/admin/home_settings/edit.html.erb", __dir__))
  end

  let(:home_settings_preview_controller) do
    File.read(File.expand_path("../../../app/javascript/controllers/home_settings_preview_controller.js", __dir__))
  end

  let(:layout_settings_edit_view) do
    File.read(File.expand_path("../../../app/views/admin/layout_settings/edit.html.erb", __dir__))
  end

  let(:layout_theme_preview_controller) do
    File.read(File.expand_path("../../../app/javascript/controllers/layout_theme_preview_controller.js", __dir__))
  end

  let(:footer_settings_views) do
    %w[footer_settings/edit.html.erb footer_settings/_footer_link_fields.html.erb footer_settings/_footer_store_fields.html.erb footer_settings/_footer_social_link_fields.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:access_audit_logs_view) do
    File.read(File.expand_path("../../../app/views/admin/access_audit_logs/index.html.erb", __dir__))
  end

  let(:page_header_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_page_header.html.erb", __dir__))
  end

  let(:page_header_consumer_views) do
    %w[
      access_audit_logs/index.html.erb
      seo_settings/new.html.erb
      seo_settings/edit.html.erb
      captacoes/show.html.erb
      home_section_items/_form.html.erb
    ].map { |path| File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__)) }
  end

  let(:fixed_layout_residue_views) do
    %w[
      access_audit_logs/index.html.erb
      dwv_integrations/_status_panel.html.erb
      system/error_events/index.html.erb
      admin_users/show.html.erb
      stores/_store_shift_fields.html.erb
    ].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:distribution_rule_form_views) do
    %w[distribution_rules/_form.html.erb distribution_rules/_form_aside.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:stores_index_view) do
    File.read(File.expand_path("../../../app/views/admin/stores/index.html.erb", __dir__))
  end

  let(:store_workspace_views) do
    %w[stores/index.html.erb stores/new.html.erb stores/edit.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:stores_show_view) do
    File.read(File.expand_path("../../../app/views/admin/stores/show.html.erb", __dir__))
  end

  let(:store_form_views) do
    %w[stores/_form.html.erb stores/_operational_shift_fields.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:push_settings_view) do
    File.read(File.expand_path("../../../app/views/admin/push_settings/edit.html.erb", __dir__))
  end

  let(:settings_step_views) do
    %w[
      push_settings/edit.html.erb
      lead_settings/edit.html.erb
      two_factor_settings/show.html.erb
      system/notification_settings/edit.html.erb
    ].map { |path| File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__)) }
  end

  let(:notification_settings_workspace_views) do
    %w[email_settings/edit.html.erb whatsapp_service_settings/edit.html.erb system/notification_settings/edit.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:lead_settings_view) do
    File.read(File.expand_path("../../../app/views/admin/lead_settings/edit.html.erb", __dir__))
  end

  let(:contact_settings_view) do
    File.read(File.expand_path("../../../app/views/admin/contact_settings/edit.html.erb", __dir__))
  end

  let(:marketing_opportunities_view) do
    File.read(File.expand_path("../../../app/views/admin/marketing_opportunities/index.html.erb", __dir__))
  end

  let(:marketing_campaign_views) do
    %w[marketing_campaigns/index.html.erb marketing_campaigns/_form.html.erb marketing_campaigns/new.html.erb marketing_campaigns/edit.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:seo_setting_form_view) do
    File.read(File.expand_path("../../../app/views/admin/seo_settings/_form.html.erb", __dir__))
  end

  let(:automation_action_row_view) do
    File.read(File.expand_path("../../../app/views/admin/automation_rules/_action_row.html.erb", __dir__))
  end

  let(:field_check_ins_index_view) do
    File.read(File.expand_path("../../../app/views/admin/field/check_ins/index.html.erb", __dir__))
  end

  let(:field_check_ins_show_view) do
    File.read(File.expand_path("../../../app/views/admin/field/check_ins/show.html.erb", __dir__))
  end

  let(:attribute_options_index_view) do
    File.read(File.expand_path("../../../app/views/admin/attribute_options/index.html.erb", __dir__))
  end

  let(:manual_checkin_request_views) do
    %w[field/manual_checkin_requests/index.html.erb field/manual_checkin_requests/show.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:data_export_audit_logs_view) do
    File.read(File.expand_path("../../../app/views/admin/data_export_audit_logs/index.html.erb", __dir__))
  end

  let(:task_views) do
    %w[tasks/index.html.erb tasks/_form_modal.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:whatsapp_integration_view) do
    File.read(File.expand_path("../../../app/views/admin/whatsapp_integrations/show.html.erb", __dir__))
  end

  let(:whatsapp_integration_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/whatsapp_integration.css", __dir__))
  end

  let(:whatsapp_templates_index_view) do
    File.read(File.expand_path("../../../app/views/admin/whatsapp_templates/index.html.erb", __dir__))
  end

  let(:system_error_events_index_view) do
    File.read(File.expand_path("../../../app/views/admin/system/error_events/index.html.erb", __dir__))
  end

  let(:system_users_view) do
    File.read(File.expand_path("../../../app/views/admin/system/users.html.erb", __dir__))
  end

  let(:whatsapp_integration_controller) do
    File.read(File.expand_path("../../../app/javascript/controllers/whatsapp_integration_controller.js", __dir__))
  end

  let(:lead_labels_manager_view) do
    File.read(File.expand_path("../../../app/views/admin/lead_labels/_manager.html.erb", __dir__))
  end

  let(:lead_label_chip_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_lead_label_chip.html.erb", __dir__))
  end

  let(:lead_labels_controller) do
    File.read(File.expand_path("../../../app/javascript/controllers/lead_labels_controller.js", __dir__))
  end

  let(:two_factor_settings_view) do
    File.read(File.expand_path("../../../app/views/admin/two_factor_settings/show.html.erb", __dir__))
  end

  let(:two_factor_backup_codes_view) do
    File.read(File.expand_path("../../../app/views/admin/two_factor_settings/backup_codes.html.erb", __dir__))
  end

  let(:home_sections_index_view) do
    File.read(File.expand_path("../../../app/views/admin/home_sections/index.html.erb", __dir__))
  end

  let(:home_section_workspace_views) do
    %w[
      home_sections/show.html.erb
      home_sections/_form.html.erb
      home_section_items/_form.html.erb
    ].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:chip_grid_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_chip_grid.html.erb", __dir__))
  end

  let(:proprietors_index_view) do
    File.read(File.expand_path("../../../app/views/admin/proprietors/index.html.erb", __dir__))
  end

  let(:lead_attend_expired_view) do
    File.read(File.expand_path("../../../app/views/admin/leads/attend_expired.html.erb", __dir__))
  end

  let(:property_settings_edit_view) do
    File.read(File.expand_path("../../../app/views/admin/property_settings/edit.html.erb", __dir__))
  end

  let(:property_settings_review_workflow_view) do
    File.read(File.expand_path("../../../app/views/admin/property_settings/review_workflow.html.erb", __dir__))
  end

  let(:workflow_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/workflow.css", __dir__))
  end

  let(:watermark_preview_controller) do
    File.read(File.expand_path("../../../app/javascript/controllers/watermark_preview_controller.js", __dir__))
  end

  let(:webhook_settings_form_view) do
    File.read(File.expand_path("../../../app/views/admin/webhook_settings/_form.html.erb", __dir__))
  end

  let(:webhook_outbound_settings_view) do
    File.read(File.expand_path("../../../app/views/admin/webhook_settings/_outbound_settings.html.erb", __dir__))
  end

  let(:marketing_alerts_index_view) do
    File.read(File.expand_path("../../../app/views/admin/marketing_alerts/index.html.erb", __dir__))
  end

  let(:marketing_properties_index_view) do
    File.read(File.expand_path("../../../app/views/admin/marketing_properties/index.html.erb", __dir__))
  end

  let(:image_migration_status_view) do
    File.read(File.expand_path("../../../app/views/admin/image_migration_status/index.html.erb", __dir__))
  end

  let(:image_migration_status_controller) do
    File.read(File.expand_path("../../../app/javascript/controllers/image_migration_status_controller.js", __dir__))
  end

  let(:storage_integration_view) do
    File.read(File.expand_path("../../../app/views/admin/storage_integrations/show.html.erb", __dir__))
  end

  let(:storage_public_photo_publish_controller) do
    File.read(File.expand_path("../../../app/javascript/controllers/storage_public_photo_publish_controller.js", __dir__))
  end

  let(:automation_events_index_view) do
    File.read(File.expand_path("../../../app/views/admin/automation_events/index.html.erb", __dir__))
  end

  let(:automation_rules_index_view) do
    File.read(File.expand_path("../../../app/views/admin/automation_rules/index.html.erb", __dir__))
  end

  let(:automation_rule_form_views) do
    %w[automation_rules/new.html.erb automation_rules/edit.html.erb automation_rules/_form.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:captacao_goal_views) do
    %w[captacao_goals/index.html.erb captacao_goals/_form.html.erb captacao_goals/new.html.erb captacao_goals/edit.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:field_settings_edit_view) do
    File.read(File.expand_path("../../../app/views/admin/field_settings/edit.html.erb", __dir__))
  end

  let(:seo_redirects_index_view) do
    File.read(File.expand_path("../../../app/views/admin/seo_redirects/index.html.erb", __dir__))
  end

  let(:field_audit_log_views) do
    %w[field/audit_logs/index.html.erb field/audit_logs/show.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:profiles_index_view) do
    File.read(File.expand_path("../../../app/views/admin/profiles/index.html.erb", __dir__))
  end

  let(:profiles_show_view) do
    File.read(File.expand_path("../../../app/views/admin/profiles/show.html.erb", __dir__))
  end

  let(:account_settings_view) do
    File.read(File.expand_path("../../../app/views/admin/account_settings/show.html.erb", __dir__))
  end

  let(:presentation_card_workspace_views) do
    %w[presentation_cards/index.html.erb presentation_cards/new.html.erb presentation_cards/edit.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:presentation_card_support_views) do
    %w[presentation_cards/_profile_preview.html.erb presentation_cards/_quick_edit_modal.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:presentation_card_form_view) do
    File.read(File.expand_path("../../../app/views/admin/presentation_cards/_form.html.erb", __dir__))
  end

  let(:profiles_form_view) do
    File.read(File.expand_path("../../../app/views/admin/profiles/_form.html.erb", __dir__))
  end

  let(:system_index_view) do
    File.read(File.expand_path("../../../app/views/admin/system/index.html.erb", __dir__))
  end

  let(:meta_integrations_index_view) do
    File.read(File.expand_path("../../../app/views/admin/meta_integrations/index.html.erb", __dir__))
  end

  let(:account_memberships_index_view) do
    File.read(File.expand_path("../../../app/views/admin/account_memberships/index.html.erb", __dir__))
  end

  let(:proprietors_edit_view) do
    File.read(File.expand_path("../../../app/views/admin/proprietors/edit.html.erb", __dir__))
  end

  let(:proprietor_form_views) do
    %w[proprietors/new.html.erb proprietors/edit.html.erb proprietors/_form.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end


  let(:landing_page_form_views) do
    %w[landing_pages/new.html.erb landing_pages/edit.html.erb landing_pages/_form.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:proposal_form_views) do
    %w[proposals/new.html.erb proposals/edit.html.erb proposals/_form.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:landing_pages_index_view) do
    File.read(File.expand_path("../../../app/views/admin/landing_pages/index.html.erb", __dir__))
  end

  let(:property_page_preview_controller) do
    File.read(File.expand_path("../../../app/javascript/controllers/property_page_preview_controller.js", __dir__))
  end

  let(:dashboard_loading_panel_view) do
    File.read(File.expand_path("../../../app/views/admin/dashboard/sections/_loading_panel.html.erb", __dir__))
  end

  let(:dashboard_operational_views) do
    %w[dashboard/sections/_rankings.html.erb dashboard/sections/_support.html.erb dashboard/sections/_funnel.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:dashboard_controller) do
    File.read(File.expand_path("../../../app/controllers/admin/dashboard_controller.rb", __dir__))
  end

  let(:pagination_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/pagination.css", __dir__))
  end

  let(:filter_section_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/filter_section.css", __dir__))
  end

  let(:sticky_action_footer_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/sticky_action_footer.css", __dir__))
  end

  let(:form_actions_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/form_actions.css", __dir__))
  end

  let(:form_actions_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_form_actions.html.erb", __dir__))
  end

  let(:form_actions_consumer_views) do
    %w[
      whatsapp_service_settings/edit.html.erb
      presentation_cards/_form.html.erb
      push_settings/edit.html.erb
      automation_rules/_form.html.erb
      system/notification_settings/edit.html.erb
    ].map { |path| File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__)) }
  end

  let(:field_grid_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_field_grid.html.erb", __dir__))
  end

  let(:field_grid_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/field_grid.css", __dir__))
  end

  let(:table_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/table.css", __dir__))
  end

  let(:card_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/card.css", __dir__))
  end

  let(:panel_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/panel.css", __dir__))
  end

  let(:panel_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_panel.html.erb", __dir__))
  end

  let(:collapsible_card_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_collapsible_card.html.erb", __dir__))
  end

  let(:disclosure_card_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/disclosure_card.css", __dir__))
  end

  let(:tooltip_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/tooltip.css", __dir__))
  end

  let(:admin_login_layout) do
    File.read(File.expand_path("../../../app/views/layouts/admin_login.html.erb", __dir__))
  end

  let(:admin_two_factor_challenge_view) do
    File.read(File.expand_path("../../../app/views/admin/sessions/two_factor.html.erb", __dir__))
  end

  let(:lead_show_view) do
    File.read(File.expand_path("../../../app/views/admin/leads/show.html.erb", __dir__))
  end

  let(:code_snippet_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/code_snippet.css", __dir__))
  end

  let(:option_card_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/option_card.css", __dir__))
  end

  let(:stack_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/stack.css", __dir__))
  end

  let(:module_objective_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/module_objective.css", __dir__))
  end

  let(:search_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/search.css", __dir__))
  end

  let(:search_consumer_views) do
    %w[stores/index.html.erb admin_users/index.html.erb proprietors/index.html.erb].map do |path|
      File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__))
    end
  end

  let(:form_control_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/form_control.css", __dir__))
  end

  let(:color_field_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/color_field.css", __dir__))
  end

  let(:color_field_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_color_field.html.erb", __dir__))
  end

  let(:board_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/board.css", __dir__))
  end

  let(:board_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_board.html.erb", __dir__))
  end

  let(:board_column_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_board_column.html.erb", __dir__))
  end

  let(:lead_label_chip_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/lead_label_chip.css", __dir__))
  end

  let(:team_toggle_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/team_toggle.css", __dir__))
  end

  let(:team_toggle_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_team_toggle.html.erb", __dir__))
  end

  let(:color_pair_controller) do
    File.read(File.expand_path("../../../app/javascript/controllers/ax_color_pair_controller.js", __dir__))
  end

  let(:form_section_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/form_section.css", __dir__))
  end

  let(:form_section_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_form_section.html.erb", __dir__))
  end

  let(:contextbar_button_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/contextbar_button.css", __dir__))
  end

  let(:form_tabs_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/form_tabs.css", __dir__))
  end

  let(:page_heading_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/page_heading.css", __dir__))
  end

  let(:workspace_heading_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/workspace_heading.css", __dir__))
  end

  let(:workspace_shell_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/workspace_shell.css", __dir__))
  end

  let(:workspace_shell_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_workspace_shell.html.erb", __dir__))
  end

  let(:button_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/button.css", __dir__))
  end

  let(:modal_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/modal.css", __dir__))
  end

  let(:menu_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/menu.css", __dir__))
  end

  let(:media_modal_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/media_modal.css", __dir__))
  end

  let(:media_preview_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/media_preview.css", __dir__))
  end

  let(:icon_button_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/icon_button.css", __dir__))
  end

  let(:loading_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/loading.css", __dir__))
  end

  let(:operational_panel_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/operational_panel.css", __dir__))
  end

  let(:operational_panel_view) do
    File.read(File.expand_path("../../../app/views/admin/shared/ui/_operational_panel.html.erb", __dir__))
  end

  let(:habitations_catalog_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/admin/habitations_catalog.css", __dir__))
  end

  let(:habitation_editor_aside_view) do
    File.read(File.expand_path("../../../app/views/admin/habitations/_editor_aside.html.erb", __dir__))
  end

  let(:habitation_media_gallery_view) do
    File.read(File.expand_path("../../../app/views/admin/habitations/media/_gallery_items.html.erb", __dir__))
  end

  let(:photo_upload_controller) do
    File.read(File.expand_path("../../../app/javascript/controllers/photo_upload_controller.js", __dir__))
  end

  let(:habitation_rich_text_views) do
    %w[
      habitations/form_tabs/empreendimento/_descricao_capacidade.html.erb
      habitations/form_tabs/shared/_seo_controle.html.erb
      habitations/form_tabs/shared/_texto_publico.html.erb
    ].map { |path| File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__)) }
  end

  let(:habitation_form_controller) do
    File.read(File.expand_path("../../../app/javascript/controllers/habitation_form_controller.js", __dir__))
  end

  let(:habitation_export_controller) do
    File.read(File.expand_path("../../../app/javascript/controllers/habitation_export_controller.js", __dir__))
  end

  let(:bulk_publish_controller) do
    File.read(File.expand_path("../../../app/javascript/controllers/bulk_publish_controller.js", __dir__))
  end

  let(:habitations_form_stylesheet) do
    File.read(File.expand_path("../../../app/assets/stylesheets/habitations_form_refresh.css", __dir__))
  end

  describe "modularizacao sem alterar a cascata" do
    let(:tokens) do
      File.read(File.expand_path("../../../app/assets/stylesheets/admin/theme_tokens.css", __dir__))
    end

    let(:admin_layout) do
      File.read(File.expand_path("../../../app/views/layouts/admin.html.erb", __dir__))
    end

    let(:wizard_layout) do
      File.read(File.expand_path("../../../app/views/layouts/captacao_wizard.html.erb", __dir__))
    end


    let(:components_bundle) do
      File.read(File.expand_path("../../../app/assets/stylesheets/admin/components.css", __dir__))
    end

    let(:component_names) do
      Dir[File.expand_path("../../../app/assets/stylesheets/admin/components/*.css", __dir__)]
        .map { |path| File.basename(path, ".css") }
        .sort
    end

    let(:bundled_component_names) do
      components_bundle.scan(%r{require admin/components/([a-z0-9_]+)}).flatten
    end

    let(:standalone_component_names) do
      [admin_layout, wizard_layout]
        .flat_map { |layout| layout.scan(/stylesheet_link_tag "admin\/components\/([^"]+)"/).flatten }
        .uniq
        .sort
    end

    it "mantem os tokens semanticos em uma fonte compartilhada" do
      %w[
        --admin-surface
        --admin-workspace-bg
        --admin-primary
        --admin-ink
        --ax-panel-bg
        --ax-border
        --ax-field-focus
        --ax-motion-base
        --ax-dark-surface
        --ax-dark-shell
        --ax-dark-border
        --ax-dark-divider
        --ax-dark-divider-soft
        --ax-dark-text
        --ax-dark-placeholder
        --ax-dark-text-soft
        --ax-dark-focus-border
        --ax-dark-focus-surface
        --ax-dark-link
        --ax-dark-danger-border
        --ax-dark-danger-surface
        --ax-dark-danger-text
        --ax-dark-warning-border
        --ax-dark-warning-surface
        --ax-dark-warning-text
        --ax-dark-success-border
        --ax-dark-success-surface
        --ax-dark-success-text
        --ax-dark-info-border
        --ax-dark-info-surface
        --ax-dark-info-text
      ].each do |token|
        expect(tokens).to include(token)
      end

      expect(stylesheet).not_to match(/:root\s*\{[^}]*--admin-surface:/m)
      expect(stylesheet).not_to include("--ax-dark-surface:")
    end

    it "resolve todos os tokens dark usados pelo admin" do
      contract_source = admin_dark_contract_paths.map { |path| File.read(path) }.join("\n")
      referenced_tokens = contract_source.scan(/var\((--ax-dark-[a-z0-9-]+)/).flatten.uniq.sort
      declared_tokens = tokens.scan(/(--ax-dark-[a-z0-9-]+)\s*:/).flatten.uniq.sort

      expect(referenced_tokens).not_to be_empty
      expect(referenced_tokens - declared_tokens).to be_empty,
        "tokens dark sem definicao: #{(referenced_tokens - declared_tokens).join(', ')}"
      expect(declared_tokens - referenced_tokens).to be_empty,
        "tokens dark declarados sem uso: #{(declared_tokens - referenced_tokens).join(', ')}"
    end

    it "isola a paleta dark e preserva os fallbacks principais do tema light" do
      root_scope = tokens[/\:root\s*\{(.*?)\n\}/m, 1]
      dark_scope = tokens[/\[data-admin-theme=["']dark["']\]\s*\{(.*?)\n\}/m, 1]

      expect(root_scope).not_to be_nil
      expect(root_scope).not_to be_empty
      expect(dark_scope).not_to be_nil
      expect(dark_scope).not_to be_empty
      expect(root_scope).not_to include("--ax-dark-")
      expect(tokens.scan(/--ax-dark-[a-z0-9-]+\s*:/)).to eq(
        dark_scope.scan(/--ax-dark-[a-z0-9-]+\s*:/)
      )

      {
        "--admin-surface" => "#ffffff",
        "--admin-surface-header" => "#eef2f7",
        "--admin-workspace-bg" => "#eef2f7",
        "--admin-sidebar-bg" => "#ffffff",
        "--admin-primary" => "#365f8f",
        "--admin-ink" => "#1f2733"
      }.each do |property, expected_value|
        expect(custom_property_value(root_scope, property)).to eq(expected_value),
          "fallback light alterado para #{property}"
      end
    end

    it "carrega tokens antes do design system em todos os layouts do admin" do
      [admin_layout, wizard_layout].each do |layout|
        expect(layout.index('stylesheet_link_tag "admin/theme_tokens"')).to be <
          layout.index('stylesheet_link_tag "admin_tailwind"')
        expect(layout.index('stylesheet_link_tag "admin_tailwind"')).to be <
          layout.index('stylesheet_link_tag "admin/components"')
      end


      component_order = %w[
        view_toggle badge alert switch toggle_chip radio_group progress presentation_cards upload file_list empty_state metric_card audience_workspace
        inline_notice record_item quick_modal clearable_control input_group field_label field_feedback
        field_group pagination
        filter_section sticky_action_footer form_actions table card page_heading button modal menu icon_button loading operational_panel
      ]

      component_order.each_cons(2) do |current, following|
        expect(components_bundle.index("require admin/components/#{current}")).to be <
          components_bundle.index("require admin/components/#{following}")
      end
    end

    it "nao deixa componentes compartilhados orfaos nem imports inexistentes" do
      expect(bundled_component_names).to eq(bundled_component_names.uniq)
      expect((bundled_component_names + standalone_component_names).sort).to eq(component_names)
      expect(standalone_component_names).to eq(["media_modal"])
    end

    it "mantem um seletor raiz referenciado no admin para cada componente carregado" do
      expect(COMPONENT_ROOT_SELECTORS.keys).to match_array(component_names)

      admin_contract_sources = (
        Dir[File.expand_path("../../../app/views/admin/**/*", __dir__)] +
        Dir[File.expand_path("../../../app/helpers/admin/**/*", __dir__)] +
        Dir[File.expand_path("../../../app/javascript/controllers/**/*", __dir__)]
      ).select { |path| File.file?(path) }.to_h { |path| [path, File.read(path)] }

      COMPONENT_ROOT_SELECTORS.each do |component_name, root_selector|
        component_source = File.read(
          File.expand_path("../../../app/assets/stylesheets/admin/components/#{component_name}.css", __dir__)
        )
        selector_pattern = /(?<![a-zA-Z0-9_-])#{Regexp.escape(root_selector)}(?![a-zA-Z0-9_-])/

        expect(component_source).to match(/\.#{Regexp.escape(root_selector)}(?![a-zA-Z0-9_-])/)
        expect(admin_contract_sources.values).to include(a_string_matching(selector_pattern)),
          "esperava encontrar uma referência ao contrato .#{root_selector} fora da folha #{component_name}.css"
      end
    end

    it "exige tratamento dark explicito ou neutralidade de tema documentada em cada componente" do
      expect(THEME_NEUTRAL_COMPONENTS).to match_array(%w[code_snippet field_grid stack])

      component_names.each do |component_name|
        component_source = File.read(
          File.expand_path("../../../app/assets/stylesheets/admin/components/#{component_name}.css", __dir__)
        )

        if THEME_NEUTRAL_COMPONENTS.include?(component_name)
          expect(component_source).not_to match(/\[data-admin-theme=["']dark["']\]/),
            "#{component_name}.css deixou de ser neutro; remova-o da allowlist e cubra o escopo dark"
        else
          expect(component_source).to match(/\[data-admin-theme=["']dark["']\]/),
            "#{component_name}.css precisa de um escopo dark explícito ou de neutralidade documentada"
        end
      end

      expect(File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/code_snippet.css", __dir__)))
        .to include("Code surface intentionally stays dark in both platform themes")

      %w[field_grid stack].each do |component_name|
        component_source = File.read(
          File.expand_path("../../../app/assets/stylesheets/admin/components/#{component_name}.css", __dir__)
        )

        expect(component_source).not_to match(/(?:color|background|border-color)\s*:/),
          "#{component_name}.css deve permanecer puramente estrutural enquanto estiver na allowlist neutra"
      end
    end
  end

  it "permite aplicar o tema dark em escopos locais dos componentes compartilhados" do
    offenders = shared_component_paths.filter_map do |path|
      next unless File.read(path).include?('html[data-admin-theme="dark"]')

      admin_stylesheet_label(path)
    end

    expect(offenders).to be_empty,
      "componentes presos ao tema dark da pagina inteira: #{offenders.join(', ')}"
  end

  it "mantem paginacao light, dark, legada e responsiva em um componente isolado" do
    expect(pagination_stylesheet).to match(/(?:^|\n)\.ax-pagination\s*\{/)
    expect(pagination_stylesheet).to match(/\.ax-pager \.pagination a/)
    expect(pagination_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-pagination\s*\{/)
    expect(pagination_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-pagination__summary/)
    expect(pagination_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-pagination__controls > a:hover/)
    expect(pagination_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-pagination__controls > a:active/)
    expect(pagination_stylesheet).to match(/\.ax-pagination__controls > a:focus-visible/)
    expect(pagination_stylesheet).to match(/data-admin-theme=["'][^"']*dark["'][^{]*\.ax-pager \.pagination a/)
    expect(pagination_stylesheet).to match(/@media \(prefers-reduced-motion: reduce\)/)
    expect(pagination_stylesheet).to match(/@media \(max-width: 720px\)[^{]*\{[^}]*\.ax-pagination/m)
    expect(system_error_events_index_view).to include("ax_pagination @error_events, params: request.query_parameters")
    expect(system_users_view).to include("ax_pagination @admin_users, params: request.query_parameters")
    expect(whatsapp_templates_index_view).to include("ax_pagination @templates, params: request.query_parameters")
    expect([system_error_events_index_view, system_users_view, whatsapp_templates_index_view].join).not_to include("will_paginate")
    expect(pagination_stylesheet).not_to include('html[data-admin-theme="dark"]')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-(?:pagination|pager)(?:__|--|\s|\.)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.ax-pagination/)
  end

  it "mantem templates WhatsApp no bundle administrativo e sem estilos injetados pela view" do
    template_views = %w[index new edit show].map do |action|
      File.read(File.expand_path("../../../app/views/admin/whatsapp_templates/#{action}.html.erb", __dir__))
    end.join("\n")

    expect(template_views).not_to include('render "critical_styles"', "<style")
    expect(whatsapp_templates_index_view).to include("ax_empty_state(", 'aria: ({ current: "true" }', 'scope="col"')
    expect(table_stylesheet).to include(".ax-table__caption--sr-only")
    expect(stylesheet).to include(".whatsapp-templates", '[data-admin-theme="dark"] .whatsapp-templates')
  end


  it "mantem a pagina atual e a navegacao indisponivel semanticamente identificadas" do
    renderer = File.read(File.expand_path("../../../config/initializers/will_paginate.rb", __dir__))

    expect(renderer).to include('"aria-current" => "page"')
    expect(renderer).to include('"aria-disabled" => "true"')
  end

  it "mantem secoes de filtro light e dark em um componente isolado" do
    expect(filter_section_stylesheet).to match(/(?:^|\n)\.ax-filter-section\s*\{/)
    expect(filter_section_stylesheet).to match(/\.ax-filter-section\[open\] > \.ax-filter-section__summary/)
    expect(filter_section_stylesheet).to match(/\.ax-filter-section__summary::after/)
    expect(filter_section_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-filter-section__summary/)
    expect(filter_section_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-filter-section__body/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-filter-section(?:__|--|\s|\[|\+)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.ax-filter-section/)
  end

  it "mantem labels e ajuda light e dark em um componente isolado" do
    expect(field_label_view).to include(
      'class="ax-field-label-wrap"',
      "label_options[:for].present?",
      "tag.span(**neutral_options)",
      'class="ax-field-label__info"'
    )
    expect(field_label_stylesheet).to match(/(?:^|\n)\.ax-field-label\s*\{/)
    expect(field_label_stylesheet).to match(/(?:^|\n)\.ax-field-label-wrap\s*\{/)
    expect(field_label_stylesheet).to match(/\.ax-field-label__text\s*\{/)
    expect(field_label_stylesheet).to match(/\.ax-field-label__info:focus-visible/)
    expect(field_label_stylesheet).to include("overflow-wrap: anywhere", 'aria-disabled="true"')
    expect(field_label_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-field-label\s*\{/)
    expect(field_label_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-field-label__info/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-field-label(?:__|--|\s)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'] :where\([^)]*\.ax-field-label/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.habitation-form-ui \.ax-field-label/)
  end

  it "mantem estrutura e hints de campo isolados sem duplicar a validacao" do
    expect(field_feedback_stylesheet).to match(/(?:^|\n)\.ax-field\s*\{/)
    expect(field_feedback_stylesheet).to match(/\.ax-field__label\s*\{/)
    expect(field_feedback_stylesheet).to match(/\.ax-field__hint\s*\{/)
    expect(field_feedback_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-field__hint/)
    expect(field_feedback_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-field__error/)
    expect(field_feedback_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*:where\([^)]*\.ax-control\.is-invalid/m)
    expect(field_feedback_stylesheet).not_to match(/(?:^|\n)\.ax-field__error\s*\{/)
    expect(validation_stylesheet).to match(/(?:^|\n)\.ax-field__error\s*\{/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-field(?:__label|__hint|\s*\{)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'] :where\([^)]*\.ax-field__hint/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.habitation-form-ui \.ax-field__hint/)
  end


  it "marca erros de campo para tecnologia assistiva sem duplicar atributos" do
    field_error_proc = File.read(File.expand_path("../../../config/initializers/field_error_proc.rb", __dir__))
    field_error_view = File.read(File.expand_path("../../../app/views/admin/shared/ui/_field_error.html.erb", __dir__))
    field_view = File.read(File.expand_path("../../../app/views/admin/shared/ui/_field.html.erb", __dir__))

    expect(field_error_proc).to include('aria-invalid="true"', 'unless tag.match?(/\baria-invalid=/)')
    expect(field_error_view).to include('class="ax-field__error" role="alert"')
    expect(field_view).to include('class="ax-field__error" role="alert"')
  end

  it "mantem footer persistente light e dark isolado com variantes escopadas" do
    sticky_action_footer_view = File.read(File.expand_path("../../../app/views/admin/shared/ui/_sticky_action_footer.html.erb", __dir__))
    ui_helper = File.read(File.expand_path("../../../app/helpers/admin/ui_helper.rb", __dir__))

    expect(sticky_action_footer_stylesheet).to match(/(?:^|\n)\.ax-sticky-action-footer\s*\{/)
    expect(sticky_action_footer_stylesheet).to match(/\.ax-sticky-action-footer\s*\{[^}]*position:\s*sticky;[^}]*bottom:\s*0;/m)
    expect(sticky_action_footer_stylesheet).to match(/\.ax-sticky-action-footer--static\s*\{[^}]*position:\s*static;/m)
    expect(sticky_action_footer_stylesheet).to include("env(safe-area-inset-bottom, 0px)")
    expect(sticky_action_footer_stylesheet).to match(/\.ax-sticky-action-footer__inner\s*\{/)
    expect(sticky_action_footer_stylesheet).to match(/\.ax-sticky-action-footer__actions\s*\{/)
    expect(sticky_action_footer_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-sticky-action-footer\s*\{/)
    expect(sticky_action_footer_stylesheet).to match(/@media \(max-width: 639px\)/)
    expect(sticky_action_footer_view).to include("<footer", 'aria-label="Ações do formulário"', "if meta.present?", '"ax-sticky-action-footer--static" unless sticky')
    expect(ui_helper).to include("def ax_sticky_action_footer(meta: nil, sticky: true")
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-sticky-action-footer(?:__|--|\s)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'] \.ax-sticky-action-footer(?:__|\s)/)
    expect(stylesheet).to include(".whatsapp-campaign-builder__footer .ax-sticky-action-footer__inner")
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.habitation-form-ui \.ax-sticky-action-footer/)
  end

  it "mantem paineis operacionais light e dark isolados com variantes escopadas" do
    expect(operational_panel_stylesheet).to match(/(?:^|\n)\.ax-operational-panel\s*\{/)
    expect(operational_panel_stylesheet).to match(/\.ax-operational-panel\s*\{[^}]*overflow:\s*visible;/m)
    expect(operational_panel_stylesheet).to match(/\.ax-operational-panel__header\s*\{/)
    expect(operational_panel_stylesheet).to match(/\.ax-operational-panel__header\s*\{[^}]*border-radius:\s*7px 7px 0 0;/m)
    expect(operational_panel_stylesheet).to match(/\.ax-operational-panel__body:has\(> \.ax-panel-body\)/)
    expect(operational_panel_stylesheet).to match(/(?:^|\n)\.ax-panel-body\s*\{/)
    expect(operational_panel_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-operational-panel\s*\{/)
    expect(operational_panel_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-operational-panel__header/)
    expect(operational_panel_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-operational-panel__header h2/)
    expect(operational_panel_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-operational-panel__eyebrow/)
    expect(operational_panel_stylesheet).to match(/@media\s*\(max-width:\s*639px\)[^{]*\{[^}]*\.ax-operational-panel__header/m)
    expect(operational_panel_view).to include('aria-label="<%= title.presence || eyebrow %>"')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-panel-body\s*\{/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-operational-panel(?:__|--|\s)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'] :where\([^)]*\.ax-operational-panel/)
    expect(stylesheet).to include(".wa-inbox-panel.ax-operational-panel")
    expect(stylesheet).to include(".whatsapp-sender-panel > .ax-operational-panel__header")
  end

  it "compartilha superficies de filtro e estados vazios em light e dark" do
    access_security_view = File.read(File.expand_path("../../../app/views/admin/access_security/show.html.erb", __dir__))
    whatsapp_views = %w[
      whatsapp_campaigns/index.html.erb
      whatsapp_campaigns/show.html.erb
      whatsapp_campaign_recipients/index.html.erb
      whatsapp_campaign_unsubscribes/index.html.erb
    ].map { |path| File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__)) }

    expect(operational_panel_stylesheet).to include(".ax-panel-body--muted")
    expect(operational_panel_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-panel-body--muted/)
    expect(table_stylesheet).to include("td.ax-table__empty")
    expect(table_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*td\.ax-table__empty/)
    expect(access_security_view.scan(/ax-panel-body--muted/).size).to eq(2)
    expect(access_security_view.scan(/ax-table__empty/).size).to eq(2)
    expect(access_security_view).not_to include(
      "access-security-help",
      "access-security-filter-bar",
      "access-security-empty-cell",
      "access-security-filter-label"
    )
    expect(whatsapp_views).to all(satisfy { |view| view.include?("ax-table__empty") })
  end

  it "mantem a integracao Meta WhatsApp legivel e navegavel em dark" do
    expect(whatsapp_integration_stylesheet).to match(/(?:^|\n)\.wa-tabs__item:focus-visible\s*\{/)
    expect(whatsapp_integration_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.wa-tabs\s*\{/)
    expect(whatsapp_integration_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.wa-workspace :where\(/)
    expect(whatsapp_integration_stylesheet).to include("var(--ax-dark-surface)", "var(--ax-dark-text)", "@media (prefers-reduced-motion: reduce)")
    expect(whatsapp_integration_view).to include('aria: ({ current: "page" }', "ax_empty_state(")
    expect(whatsapp_integration_view.scan("ax_empty_state(").size).to be >= 2
    expect(File.read(File.expand_path("../../../app/assets/stylesheets/admin/components.css", __dir__))).to include("require admin/components/whatsapp_integration")
  end

  it "mantem campanhas WhatsApp semanticamente identificadas nos estados dark compartilhados" do
    index_view = File.read(File.expand_path("../../../app/views/admin/whatsapp_campaigns/index.html.erb", __dir__))
    show_view = File.read(File.expand_path("../../../app/views/admin/whatsapp_campaigns/show.html.erb", __dir__))

    expect(index_view.scan('class="ax-table__caption--sr-only"').size).to eq(2)
    expect(show_view.scan('class="ax-table__caption--sr-only"').size).to eq(1)
    expect(index_view.scan('scope="col"').size).to eq(12)
    expect(show_view.scan('scope="col"').size).to eq(7)
    expect([index_view, show_view].join).to include("ax_empty_state(", 'aria-label="Progresso da campanha')
    expect(table_stylesheet).to include(".ax-table__caption--sr-only")
  end

  it "mantem o builder de campanhas navegavel por teclado e legivel em dark" do
    form_view = File.read(File.expand_path("../../../app/views/admin/whatsapp_campaigns/_form.html.erb", __dir__))
    controller = File.read(File.expand_path("../../../app/javascript/controllers/whatsapp_campaign_builder_controller.js", __dir__))
    component = File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/whatsapp_campaign_builder.css", __dir__))

    expect(form_view).to include('role="tablist"', 'role="tab"', 'role="tabpanel"', 'role="progressbar"')
    expect(form_view.scan('role="tabpanel"').size).to eq(5)
    expect(form_view).to include("keydown->whatsapp-campaign-builder#navigateSteps", 'aria-controls="whatsapp-campaign-step-panel-')
    expect(controller).to include('navigateSteps(event)', '"ArrowLeft"', '"ArrowRight"', '"Home"', '"End"')
    expect(controller).to include('button.setAttribute("aria-selected"', 'button.setAttribute("tabindex"', 'element.setAttribute("aria-hidden"')
    expect(component).to match(/\.whatsapp-campaign-builder__step:focus-visible\s*\{/)
    expect(component).to match(/data-admin-theme=["']dark["'][^{]*\.whatsapp-campaign-builder__nav/)
    expect(component).to include("@media (prefers-reduced-motion: reduce)")
  end

  it "mantem as bases de campanhas Meta escopadas e semanticamente identificadas" do
    recipients_controller = File.read(File.expand_path("../../../app/controllers/admin/whatsapp_campaign_recipients_controller.rb", __dir__))
    unsubscribes_controller = File.read(File.expand_path("../../../app/controllers/admin/whatsapp_campaign_unsubscribes_controller.rb", __dir__))

    expect(whatsapp_campaign_recipients_view).not_to include("WhatsappCampaignRecipient.all")
    expect(whatsapp_campaign_unsubscribes_view).not_to include("WhatsappCampaignUnsubscribe.active", "WhatsappCampaignUnsubscribe.reenabled")
    expect(recipients_controller).to include("current_tenant.whatsapp_campaign_recipients", "visible_recipients_scope", "recipient_metrics")
    expect(unsubscribes_controller).to include("current_tenant.whatsapp_campaign_unsubscribes", "visible_unsubscribes_scope", "unsubscribe_metrics")
    expect(whatsapp_campaign_recipients_view).to include('class="ax-table__caption--sr-only"', 'scope="col"', "ax_empty_state(")
    expect(whatsapp_campaign_unsubscribes_view).to include('class="ax-table__caption--sr-only"', 'scope="col"', "ax_empty_state(", "Motivo da reabilitação de")
  end

  it "mantem navegacao por teclado e semantica acessivel nas abas compartilhadas" do
    tabs_controller = File.read(File.expand_path("../../../app/javascript/controllers/ax_tabs_controller.js", __dir__))

    expect(tabs_controller).to include(
      "this.initializeState()",
      'this.element.addEventListener("keydown", this.handleKeydownBound)',
      'tab.setAttribute("aria-selected", active ? "true" : "false")',
      'tab.setAttribute("tabindex", active ? "0" : "-1")',
      'tab.setAttribute("aria-controls", panelId)',
      "this.panelsFor(content)",
      "content.contains(panel)",
      "tabDisabled(tab)",
      'tabPane.setAttribute("role", "tabpanel")',
      'tabPane.setAttribute("aria-labelledby", owningTab.id)',
      "tabPane.hidden = !active",
      'tabPane.setAttribute("aria-hidden", active ? "false" : "true")',
      '["ArrowLeft"]',
      '["ArrowRight"]',
      'event.key === "Home"',
      'event.key === "End"',
      "nextTab.focus()",
      'nextTab.scrollIntoView({ block: "nearest", inline: "nearest" })'
    )
    expect(tabs_controller).to include('this.element.removeEventListener("keydown", this.handleKeydownBound)')
    expect(tracking_integrations_view).to include(
      'id="google-tag-manager-tab"',
      'aria-labelledby="google-tag-manager-tab"',
      'id="meta-pixel-tab"',
      'aria-labelledby="meta-pixel-tab"'
    )
    expect(captacoes_dashboard_view.scan(/role="tab"/).size).to eq(4)
    expect(captacoes_dashboard_view.scan(/role="tabpanel"/).size).to eq(4)
    expect(captacoes_dashboard_view.scan(/aria-labelledby="tab-[^"]+-trigger"/).size).to eq(4)
  end

  it "mantem acoes persistentes de formulario light e dark isoladas" do
    expect(form_actions_stylesheet).to match(/(?:^|\n)\.ax-form-actions\s*\{/)
    expect(form_actions_stylesheet).to include("position: sticky")
    expect(form_actions_stylesheet).to include("backdrop-filter: blur(8px)")
    expect(form_actions_stylesheet).to match(/\.ax-form-actions--static\s*\{\s*position:\s*static;/)
    expect(form_actions_stylesheet).to match(/\.ax-form-actions\[aria-busy=["']true["']\]/)
    expect(form_actions_stylesheet).to match(/@media \(max-width: 639px\)[^{]*\{[^}]*\.ax-form-actions/m)
    expect(form_actions_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-form-actions\s*\{/)
    expect(form_actions_view).to include('"ax-form-actions--static" unless sticky', "body.present?", "form.submit submit_label")
    expect(form_actions_consumer_views).to all(include("ax_form_actions"))
    expect(form_actions_consumer_views.join).not_to include('<div class="ax-form-actions')
    expect(form_actions_consumer_views.last.scan("sticky: false").size).to eq(4)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-form-actions\s*\{/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'] \.ax-form-actions/)
    expect(stylesheet).to include('html[data-admin-theme="dark"] .layout-settings-actions')
  end

  it "mantem o grid de campos no componente compartilhado sem CSS inline" do
    expect(field_grid_view).not_to match(/<style|\bstyle\s*=/i)
    expect(field_grid_view).to include('"ax-field-grid"', '"ax-field-grid--#{columns}"', '"ax-field-grid--#{gap}"', "tag.div(class: grid_classes, data:)")
    expect(field_grid_stylesheet).to match(/\.ax-field-grid\s*\{[^}]*grid-template-columns:\s*repeat\(2,/m)
    expect(field_grid_stylesheet).to match(/\.ax-field-grid > \*\s*\{[^}]*min-width:\s*0;/m)
    expect(field_grid_stylesheet).to match(/\.ax-field-grid--12,[^{]*\{[^}]*grid-template-columns:\s*repeat\(12,/m)
    (1..12).each { |span| expect(field_grid_stylesheet).to include(".ax-field-grid > .ax-span-#{span}") }
    expect(field_grid_stylesheet).to match(/@media \(max-width: 620px\)[\s\S]*?\.ax-field-grid,[^{]*\{[^}]*grid-template-columns:\s*1fr;/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-field-grid\s*\{/)
  end

  it "mantem secoes de formulario acessiveis light e dark em um componente isolado" do
    expect(form_section_stylesheet).to match(/(?:^|\n)\.ax-form-section\s*\{/)
    expect(form_section_stylesheet).to match(/\.ax-form-section__title > span\s*\{[^}]*overflow-wrap:\s*anywhere;/m)
    expect(form_section_stylesheet).to match(/\.ax-form-section__toggle:focus-visible\s*\{[^}]*outline:\s*2px solid var\(--ax-field-focus\)/m)
    expect(form_section_stylesheet).to match(/@media \(max-width: 768px\)[\s\S]*\.ax-form-section__meta/)
    expect(form_section_stylesheet).to match(/@media \(prefers-reduced-motion: reduce\)[\s\S]*\.ax-form-section__toggle/)
    expect(form_section_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-form-section\s*\{/)
    expect(form_section_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-form-section__toggle:hover/)
    expect(form_section_view).to include('aria: { label: title }', 'section_body_options[:role] = "region"')
    expect(form_section_view).to include('aria-label="Alternar seção <%= title %>"', 'aria-controls="<%= section_collapse_id %>"')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-form-section(?:__|--|\s*\{)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["']\]\s+\.ax-form-section(?:__|\s*\{)/)
    expect(stylesheet).to include(".habitation-form-ui .ax-form-section__body")
  end

  it "mantem o par de cor sincronizado e tematico em um componente isolado" do
    expect(color_field_stylesheet).to match(/(?:^|\n)\.ax-color-control\s*\{/)
    expect(color_field_stylesheet).to match(/\.ax-color-control:hover\s*\{/)
    expect(color_field_stylesheet).to match(/\.ax-color-control:focus-within\s*\{[^}]*var\(--admin-primary-ring\)/m)
    expect(color_field_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-color-control/)
    expect(color_field_stylesheet).to match(/@media \(max-width: 420px\)[\s\S]*grid-template-columns:\s*72px/)
    expect(color_field_stylesheet).to match(/@media \(prefers-reduced-motion: reduce\)[\s\S]*\.ax-color-control/)
    expect(color_field_view).not_to include("oninput", "html_safe")
    expect(color_field_view).to include('data-controller="ax-color-pair"', 'color_options[:id] ||= "#{form.field_id(method)}_picker"')
    expect(color_field_view).to include('color_data[:ax_color_pair_target] = "swatch"', 'text_data[:ax_color_pair_target] = "text"')
    expect(color_field_view).to include('input->ax-color-pair#sync', 'aria: { label: swatch_title.presence || "Escolha a cor de #{label}" }')
    expect(color_pair_controller).to include('static targets = ["swatch", "text"]', 'event.currentTarget === this.swatchTarget')
    expect(color_pair_controller).to include('/^#[0-9a-f]{6}$/i.test(value)', 'this.textTarget.value = this.swatchTarget.value.toUpperCase()')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-color-(?:control|field)(?:__|:|\s*\{)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.ax-color-control/)
  end

  it "mantem boards densos, acessiveis e tematicos em um componente isolado" do
    expect(board_stylesheet).to match(/(?:^|\n)\.ax-board\s*\{/)
    expect(board_stylesheet).to match(/\.ax-board__card-link:focus-visible\s*\{[^}]*outline:\s*2px solid var\(--admin-primary-ring\)/m)
    expect(board_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-board__column\s*\{/)
    expect(board_stylesheet).to match(/@media \(max-width: 991\.98px\)[\s\S]*\.ax-board__card-mobile\s*\{\s*display:\s*block;/)
    expect(board_stylesheet).to match(/@media \(prefers-reduced-motion: reduce\)[\s\S]*\.ax-board__card\s*\{\s*transition:\s*none;/)
    expect(board_view).to include('role: "region"', 'local_assigns[:label].presence || "Quadro de trabalho"')
    expect(board_column_view).to include('aria-label="<%= title %>"', 'live: "polite"', 'atomic: true')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-board(?:__|--|\s*\{)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["']\]\s+\.ax-leads-board\s+\.ax-board__(?:column|col-head|card)(?:\s*\{|__)/)
    expect(stylesheet).to include(".ax-leads-board .ax-board__col-body.lead-kanban-column--active")
    expect(stylesheet).to include(".lead-kanban-card--dragging")
  end

  it "mantem chips de etiqueta legiveis em Leads e WhatsApp nos dois temas" do
    expect(lead_label_chip_stylesheet).to match(/(?:^|\n)\.lead-label-chip\s*\{[^}]*max-width:\s*100%;[^}]*overflow-wrap:\s*anywhere;/m)
    %w[gray green amber red blue purple cyan custom].each do |tone|
      expect(lead_label_chip_stylesheet).to include(".lead-label-chip--#{tone}")
      expect(lead_label_chip_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.lead-label-chip--#{tone}/)
    end
    expect(lead_label_chip_stylesheet).to match(/@media \(max-width: 420px\)[\s\S]*\.lead-label-chip/)
    expect(lead_label_chip_stylesheet).to include("var(--label-color, #667085)")
    expect(stylesheet).not_to match(/(?:^|\n)\.lead-labels-chips\s*\{/)
    expect(stylesheet).not_to match(/(?:^|\n)\.lead-label-chip(?:--|\s*\{)/)
    expect(stylesheet).to include(".wa-inbox-conversation__labels:has(.lead-label-chip)")
    expect(stylesheet).to include(".lead-list-row__labels")
  end

  it "mantem o recorte por equipe visivel, focavel e tematico" do
    expect(team_toggle_stylesheet).to match(/(?:^|\n)\.ax-team-toggle\s*\{/)
    expect(team_toggle_stylesheet).to match(/\.ax-team-toggle \.ax-toggle-chip__box\s*\{[^}]*display:\s*inline-grid;/m)
    expect(team_toggle_stylesheet).to match(/\.ax-team-toggle:focus-visible\s*\{[^}]*outline:\s*2px solid var\(--admin-primary-ring\)/m)
    expect(team_toggle_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-team-toggle \.ax-toggle-chip__box/)
    expect(team_toggle_stylesheet).to match(/@media \(prefers-reduced-motion: reduce\)[\s\S]*\.ax-team-toggle/)
    expect(team_toggle_view).to include('role: "switch"', '"aria-checked": checked.to_s')
    expect(team_toggle_view).to include('checked ? "Não incluir registros da equipe" : "Incluir registros da equipe"')
    expect(team_toggle_view).to include('request.query_parameters.merge("team" => (checked ? "0" : "1")).except("page")')
  end

  it "mantem tabelas densas light e dark isoladas sem apagar variantes de modulo" do
    expect(table_stylesheet).to match(/(?:^|\n)\.ax-table-wrap\s*\{/)
    expect(table_stylesheet).to match(/\.ax-table-wrap\s*\{[^}]*overflow-x:\s*auto;[^}]*overscroll-behavior-inline:\s*contain;/m)
    expect(table_stylesheet).to match(/(?:^|\n)\.ax-table\s*\{/)
    expect(table_stylesheet).to match(/\.ax-table tbody tr:hover td,[^{]*\.ax-table tbody tr:focus-within td\s*\{/m)
    expect(table_stylesheet).to match(/\.ax-table a:focus-visible\s*\{[^}]*outline:\s*2px solid var\(--admin-primary-ring\)/m)
    expect(table_stylesheet).to match(/@media\s*\(max-width:\s*639px\)[^{]*\{[^}]*\.ax-table thead th/m)
    expect(table_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-table thead th/)
    expect(table_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-table tbody tr:hover td,[^{]*\.ax-table tbody tr:focus-within td/m)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-table(?:-wrap|\s*\{)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["']\s+\.ax-table (?:thead|tbody)/)
    expect(stylesheet).to include(".captacoes-workspace .captacoes-table-wrap .ax-table")
    expect(stylesheet).to include(".distribution-rules-index__table .ax-table")
  end

  it "mantem cards e cards colapsaveis light e dark isolados com variantes escopadas" do
    expect(card_stylesheet).to match(/(?:^|\n)\.ax-card\s*\{/)
    expect(card_stylesheet).to match(/\.ax-card__header\s*\{/)
    expect(card_stylesheet).to match(/\.ax-collapse-card__trigger\s*\{/)
    expect(card_stylesheet).to match(/\.ax-collapse-card__trigger:focus-visible\s*\{[^}]*outline:\s*2px solid var\(--admin-primary-ring\)/m)
    expect(card_stylesheet).to include(".ax-collapse-card__trigger:hover .ax-card__title")
    expect(card_stylesheet).to match(/\.ax-collapse-card\.is-open \.ax-collapse-card__chevron/)
    expect(card_stylesheet).to match(/@media\s*\(max-width:\s*639px\)[^{]*\{[^}]*\.ax-card__header/m)
    expect(card_stylesheet).to match(/@media\s*\(prefers-reduced-motion:\s*reduce\)[^{]*\{[^}]*\.ax-collapse-card__trigger/m)
    expect(card_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-card\s*\{/)
    expect(card_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-card__header/)
    expect(card_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-collapse-card__trigger:hover/)
    expect(collapsible_card_view).to include('aria-labelledby="<%= collapse_id %>_trigger"', 'id="<%= collapse_id %>_trigger"')
    expect(collapsible_card_view).to include('aria-expanded="<%= !collapsed %>"', 'aria-controls="<%= collapse_id %>"')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-card(?:__|--|\s*\{)/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-collapse-card(?:__|\.|:)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'] :where\([^)]*\.ax-card/)
    expect(stylesheet).to include(".lead-show-workspace .ax-card__header")
    expect(stylesheet).to include(".capt-dashboard-workspace .ax-card__header")
  end

  it "mantem paineis genericos light e dark em um componente isolado" do
    expect(panel_stylesheet).to match(/(?:^|\n)\.ax-panel\s*\{/)
    expect(panel_stylesheet).to match(/\.ax-panel__trigger:focus-visible\s*\{[^}]*outline:\s*2px solid var\(--ax-field-focus\)/m)
    expect(panel_stylesheet).to match(/\.ax-panel__title\s*\{[^}]*overflow-wrap:\s*anywhere;/m)
    expect(panel_stylesheet).to match(/@media \(max-width: 767px\)[\s\S]*\.ax-panel__actions/)
    expect(panel_stylesheet).to match(/@media \(prefers-reduced-motion: reduce\)[\s\S]*\.ax-panel__chevron/)
    expect(panel_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-panel\s*\{/)
    expect(panel_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-panel__header/)
    expect(panel_view).to include('panel_classes = ["ax-panel"', 'aria-label="<%= title %>"')
    expect(panel_view).to include('data-ax-disclosure-target="content" role="region"', 'aria-label="<%= title %>"', 'aria-expanded="<%= !collapsed %>"')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-panel(?:__|--|\s*\{)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.ax-panel(?:__|\s*\{)/)
    expect(stylesheet).to include(".layout-settings-workspace .ax-panel")
  end

  it "mantem o shell de workspace estrutural e tematico em um componente isolado" do
    expect(workspace_shell_stylesheet).to match(/(?:^|\n)\.ax-workspace-shell\s*\{/)
    expect(workspace_shell_stylesheet).to match(/\.ax-workspace-shell\.is-inspector-collapsed/)
    expect(workspace_shell_stylesheet).to match(/\.ax-workspace-main\s*\{[^}]*grid-column:\s*1;/m)
    expect(workspace_shell_stylesheet).to match(/\.ax-workspace-aside\s*\{[^}]*grid-column:\s*2;/m)
    expect(workspace_shell_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-workspace-contextbar/)
    expect(workspace_shell_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-workspace-aside/)
    expect(workspace_shell_stylesheet).to match(/@media \(prefers-reduced-motion: reduce\)[\s\S]*\.ax-workspace-shell/)
    expect(workspace_shell_view).not_to match(/\bstyle\s*=/i)
    expect(workspace_shell_view).to include('"ax-workspace-shell--aside-first" if aside_first', 'aria: { label: local_assigns[:main_label].presence || "Conteúdo principal" }')
    expect(workspace_shell_view).to include('aria: { label: local_assigns[:aside_label].presence || "Painel contextual" }')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-workspace-(?:shell|main|contextbar|aside)(?:\s*\{|__[\w-]+\s*\{)/)
  end

  it "mantem disclosure cards light e dark em um componente isolado" do
    expect(disclosure_card_stylesheet).to match(/(?:^|\n)\.ax-disclosure-card\s*\{/)
    expect(disclosure_card_stylesheet).to match(/\.ax-disclosure-card\[open\] \.ax-disclosure-card__chevron/)
    expect(disclosure_card_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-disclosure-card:hover/)
    expect(disclosure_card_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-disclosure-card__body/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-disclosure-card(?:__|\[|:|\s*\{)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.ax-disclosure-card/)
    expect(stylesheet).to include(".distribution-rule-webhook-example .ax-disclosure-card__body")
  end

  it "mantem relacionamentos acessiveis e movimento reduzido nos disclosures compartilhados" do
    disclosure_controller = File.read(File.expand_path("../../../app/javascript/controllers/ax_disclosure_controller.js", __dir__))

    expect(disclosure_controller).to include(
      "this.assignRelationships()",
      "this.disclosureTriggers",
      'trigger.setAttribute("aria-controls", this.contentTarget.id)',
      'trigger.setAttribute("aria-expanded", open ? "true" : "false")',
      'this.contentTarget.setAttribute("aria-hidden", open ? "false" : "true")',
      '[data-action~="ax-disclosure#toggle"]',
      'trigger.closest(\'[data-controller~="ax-disclosure"]\') === this.element',
      'window.matchMedia?.("(prefers-reduced-motion: reduce)")'
    )
    expect(disclosure_card_stylesheet).to include(
      ".ax-disclosure-card__summary:focus-visible",
      '[data-admin-theme="dark"] .ax-disclosure-card__summary:focus-visible',
      "@media (prefers-reduced-motion: reduce)"
    )
  end

  it "mantem painel e rail do aside fora da navegacao quando estao ocultos" do
    aside_controller = File.read(File.expand_path("../../../app/javascript/controllers/ax_aside_controller.js", __dir__))
    aside_partial = File.read(File.expand_path("../../../app/views/admin/shared/ui/_aside_panel.html.erb", __dir__))
    aside_stylesheet = File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/aside_panel.css", __dir__))
    leads_view = File.read(File.expand_path("../../../app/views/admin/leads/index.html.erb", __dir__))

    expect(aside_stylesheet).to match(/(?:^|\n)\.ax-aside-panel-shell\s*\{/)
    expect(aside_stylesheet).to include(
      ".ax-aside-panel__toggle:focus-visible",
      ".ax-aside-rail-nav__item:focus-visible",
      '[data-admin-theme="dark"] .ax-aside-panel',
      "@media (prefers-reduced-motion: reduce)"
    )
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-aside-panel-shell\s*\{/)
    expect(aside_partial).to include(
      '<%= toggle_target_attribute %>="rail"',
      '<%= toggle_target_attribute %>="rail toggle"',
      '<%= toggle_target_attribute %>="panel"'
    )
    expect(aside_controller).to include(
      'static targets = ["toggle", "panel", "rail"]',
      'this.panelTarget.toggleAttribute("inert", !expanded)',
      'this.railTarget.toggleAttribute("inert", expanded)',
      'button.setAttribute("aria-controls", this.panelTarget.id)',
      "this.focusWillBeHidden(activeElement, collapsed)",
      "this.visibleToggle(collapsed)?.focus()"
    )
    expect(leads_view).to include(
      'class="ax-leads-filter-overlay" aria-label="Filtros do funil" data-ax-aside-target="panel"',
      'data-ax-aside-target="rail toggle"'
    )
  end

  it "mantem confirmacoes destrutivas acessiveis e legiveis nos dois temas" do
    confirm_controller = File.read(File.expand_path("../../../app/javascript/controllers/ax_confirm_submit_controller.js", __dir__))
    confirm_stylesheet = File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/confirm_submit.css", __dir__))
    confirm_partial = File.read(File.expand_path("../../../app/views/admin/shared/ui/_confirm_submit.html.erb", __dir__))
    confirm_consumers = %w[
      access_security/show.html.erb
      leads/index.html.erb
      habitations/form_tabs/_documents.html.erb
    ].map { |path| File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__)) }

    expect(confirm_stylesheet).to match(/(?:^|\n)\.ax-confirm-submit\s*\{/)
    expect(confirm_stylesheet).to match(/\.ax-confirm-submit\s*\{[^}]*flex-wrap:\s*wrap;/m)
    expect(confirm_stylesheet).to include(
      ".ax-confirm-submit__btn:focus-visible",
      ".ax-confirm-submit__btn:disabled",
      '[data-admin-theme="dark"] .ax-confirm-submit__panel',
      "@media (max-width: 640px)",
      "@media (prefers-reduced-motion: reduce)"
    )
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-confirm-submit\s*\{/)
    expect(confirm_controller).to include(
      'panel.setAttribute("role", "alertdialog")',
      'panel.setAttribute("aria-label", this.messageValue)',
      'if (event.key === "Escape") this.cancel(event)',
      "cancelButton.focus()",
      'confirmButton.setAttribute("aria-busy", "true")',
      'this.closeConfirmation({ restoreFocus: true })',
      'panel.closest(".is-confirming")?.classList.remove("is-confirming")',
      "this.previouslyFocusedElement.focus()"
    )
    expect(confirm_partial).to include(
      '"ax-confirm-submit"',
      "tag.div(class: wrapper_classes",
      'controller: "ax-confirm-submit"',
      "ax_confirm_submit_form_id_value: form_id",
      "ax_confirm_submit_message_value: message"
    )
    expect(confirm_consumers).to all(include("ax_confirm_submit("))
    expect(confirm_consumers).to all(satisfy { |view| !view.include?('data-controller="ax-confirm-submit"') })
  end

  it "mantem tooltips acessiveis, contidos no viewport e isolados em um componente" do
    tooltip_controller = File.read(File.expand_path("../../../app/javascript/controllers/ax_tooltip_controller.js", __dir__))

    expect(tooltip_stylesheet).to match(/(?:^|\n)\.ax-tooltip\s*\{/)
    expect(tooltip_stylesheet).to include(
      "position: fixed",
      "max-width: min(320px, calc(100vw - 16px))",
      '[data-admin-theme="dark"] .ax-tooltip',
      "@media (prefers-reduced-motion: reduce)"
    )
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-tooltip\s*\{/)
    expect(tooltip_controller).to include(
      'tip.setAttribute("role", "tooltip")',
      'this.element.setAttribute("aria-describedby", describedBy)',
      'this.element.removeAttribute("aria-describedby")',
      "this.prepareHost()",
      'this.element.setAttribute("tabindex", "0")',
      'this.element.removeAttribute("title")',
      'window.addEventListener("resize", this.position)',
      'window.addEventListener("scroll", this.position, true)',
      'if (event.key === "Escape") this.hide()',
      '["top", "bottom", "left", "right"]',
      "window.innerWidth",
      "window.innerHeight"
    )
    expect(tooltip_controller).to include(
      "get tooltipText()",
      "this.hasTextValue ? this.textValue : this.nativeTitle"
    )
    expect(tooltip_stylesheet).to include("max-height: calc(100dvh - 16px)")
  end


  it "usa o tooltip compartilhado no badge informativo em vez de title nativo" do
    info_badge = File.read(File.expand_path("../../../app/views/admin/shared/ui/_info_badge.html.erb", __dir__))

    expect(info_badge).to include('controller: "ax-tooltip"', "ax_tooltip_text_value: tooltip")
    expect(info_badge).not_to include('title="<%= tooltip %>"')
    expect(badge_stylesheet).to match(/(?:^|\n)\.ax-info-badge\s*\{/)
    expect(badge_stylesheet).to match(/\.ax-info-badge:focus-visible/)
    expect(badge_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-info-badge\s*\{/)
  end

  it "mantem o drawer global inacessivel quando fechado e preso ao foco quando aberto" do
    drawer_controller = File.read(File.expand_path("../../../app/javascript/controllers/ax_drawer_controller.js", __dir__))
    drawer_stylesheet = File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/drawer.css", __dir__))
    admin_layout = File.read(File.expand_path("../../../app/views/layouts/admin.html.erb", __dir__))

    expect(drawer_stylesheet).to match(/(?:^|\n)\.ax-drawer-backdrop\s*\{/)
    expect(drawer_stylesheet).to include(
      ".ax-drawer-panel",
      '[data-admin-theme="dark"] .ax-drawer-backdrop',
      "@media (prefers-reduced-motion: reduce)"
    )
    expect(stylesheet).not_to include(
      ".ax-drawer-backdrop { position: fixed",
      ".ax-drawer-panel { transition:"
    )
    expect(admin_layout).to include('class="ax-sidebar ax-drawer-panel"')
    expect(drawer_controller).to include(
      'this.panelTarget.toggleAttribute("inert", !this.isOpen)',
      'this.panelTarget.setAttribute("aria-hidden", this.isOpen ? "false" : "true")',
      'trigger.setAttribute("aria-controls", this.panelTarget.id)',
      'trigger.setAttribute("aria-expanded", expanded ? "true" : "false")',
      'event.key === "Escape"',
      'event.key !== "Tab"',
      "this.previouslyFocusedElement.focus()",
      'window.matchMedia("(max-width: 1023.98px)")',
      'this.drawerMedia.addEventListener("change", this.onViewportChange)',
      'document.documentElement.style.overflow = "hidden"'
    )
  end

  it "mantem snippets de codigo em um componente isolado e sempre escuro" do
    code_snippet_view = File.read(File.expand_path("../../../app/views/admin/shared/ui/_code_snippet.html.erb", __dir__))
    code_snippet_consumers = %w[
      distribution_rules/_form.html.erb
      webhook_settings/_form.html.erb
      system/error_events/show.html.erb
      field/audit_logs/show.html.erb
    ].map { |path| File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__)) }

    expect(code_snippet_stylesheet).to match(/(?:^|\n)\.ax-code-snippet\s*\{/)
    expect(code_snippet_stylesheet).to include("background: #0f1b2d")
    expect(code_snippet_stylesheet).to include("color: #cbd5e1")
    expect(code_snippet_stylesheet).to include("max-height: min(420px, 60vh)", ".ax-code-snippet pre:focus-visible", "@media (max-width: 639px)")
    expect(code_snippet_stylesheet).not_to include("data-admin-theme")
    expect(code_snippet_view).to include('tabindex="0"', 'aria-label="<%= accessible_label %>"', "<code><%= code %></code>")
    expect(code_snippet_consumers).to all(include("ax_code_snippet("))
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-code-snippet(?:__|\s*\{)/)
    expect(stylesheet).not_to include(".webhook-settings-aside-panel .ax-code-snippet", ".webhook-examples-grid .ax-code-snippet", ".webhook-editor-payload")
  end

  it "mantem option cards e seus estados interativos em um componente isolado" do
    expect(option_card_stylesheet).to match(/(?:^|\n)\.ax-option-card\s*\{/)
    expect(option_card_stylesheet).to match(/\.ax-option-card__input:focus-visible \+ \.ax-option-card/)
    expect(option_card_stylesheet).to match(/\.ax-option-card__input:checked \+ \.ax-option-card/)
    expect(option_card_stylesheet).to match(/\.ax-option-card__input:disabled \+ \.ax-option-card/)
    expect(option_card_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-option-card__input:not\(:disabled\) \+ \.ax-option-card:hover/)
    expect(option_card_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-option-card__input:checked/)
    expect(option_card_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-option-card__input:disabled/)
    expect(option_card_stylesheet).to match(/@media \(max-width: 639px\)/)
    expect(option_card_stylesheet).to match(/@media \(prefers-reduced-motion: reduce\)/)
    expect(File.read(File.expand_path("../../../app/views/admin/distribution_rules/_form_aside.html.erb", __dir__))).to include('class="bi bi-<%= icon %>" aria-hidden="true"')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-option-card(?:__|:|\s*\{)/)
    expect(stylesheet).not_to match(/data-admin-theme=["'][^"']+["'][^{]*\.distribution-rule-workspace \.ax-option-card\s*\{/)
    expect(stylesheet).not_to match(/data-admin-theme=["'][^"']+["'][^{]*\.distribution-rule-workspace \.ax-option-card:(?:hover|focus-within)/)
    expect(stylesheet).not_to match(/data-admin-theme=["'][^"']+["'][^{]*\.distribution-rule-workspace \.ax-option-card__input:checked \+ \.ax-option-card\s*\{/)
    expect(stylesheet).to include(".ax-option-card__input:checked + .distribution-rule-mode strong")
  end

  it "mantem stacks estruturais compartilhados fora do legado" do
    expect(stack_stylesheet).to match(/(?:^|\n)\.ax-option-stack,/)
    expect(stack_stylesheet).to match(/\.ax-record-list\s*\{/)
    expect(stack_stylesheet).to include("min-width: 0")
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-option-stack(?:,|\s*\{)/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-record-list\s*\{/)
    expect(stylesheet).to include(".habitation-form-ui .ax-record-list")
  end

  it "mantem o objetivo dos modulos light e dark em um componente isolado" do
    expect(module_objective_stylesheet).to match(/(?:^|\n)\.ax-module-objective\s*\{/)
    expect(module_objective_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-module-objective\s*\{/)
    expect(module_objective_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-module-objective__copy small/)
    expect(module_objective_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-module-objective__copy span/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-module-objective(?:__|\s*\{)/)
  end

  it "mantem a busca compacta light e dark em um componente isolado" do
    expect(search_stylesheet).to match(/(?:^|\n)\.ax-search\s*\{/)
    expect(search_stylesheet).to include("data:image/svg+xml")
    expect(search_stylesheet).to include(".ax-search--fluid", ".ax-search:hover:not(:disabled):not([readonly])")
    expect(search_stylesheet).to match(/\.ax-field > \.ax-search\s*\{[^}]*flex:\s*0 0 var\(--ax-form-control-height, 34px\)/m)
    expect(search_stylesheet).to include(".ax-search:focus-visible", ".ax-search::-webkit-search-cancel-button")
    expect(search_stylesheet).to include("@media (prefers-reduced-motion: reduce)")
    expect(search_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-search::placeholder/)
    expect(search_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-search:focus-visible/)
    expect(search_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-search:disabled/)
    expect(search_consumer_views.sum { |view| view.scan(/class:\s*"[^"]*\bax-search\b/).size }).to eq(3)
    expect(search_consumer_views[1]).to include("ax_text_field(", "type: :search", 'class: "ax-search ax-search--fluid"')
    expect(search_consumer_views[2]).to include("f.search_field :name", 'class: "ax-search ax-search--fluid"')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-search(?:\s*\{|:)/)
    expect(stylesheet).not_to match(/data-admin-theme=["'][^"']+["'][^{]*\.ax-search/)
  end

  it "mantem inputs, selects e textareas nativos light e dark em um componente isolado" do
    expect(form_control_stylesheet).to match(/(?:^|\n)\.ax-input,/)
    expect(form_control_stylesheet).to match(/\.ax-select:focus/)
    expect(form_control_stylesheet).to match(/\.ax-textarea\s*\{/)
    expect(form_control_stylesheet).to include('.ax-control:not(:disabled):not([readonly]):hover')
    expect(form_control_stylesheet).to include(':where(.ax-input, .ax-select, .ax-textarea):is(:disabled, [readonly])')
    expect(form_control_stylesheet).to include(':-webkit-autofill', '-webkit-text-fill-color: var(--ax-dark-text)')
    expect(form_control_stylesheet).to match(/@media\s*\(max-width:\s*767\.98px\)[^{]*\{[^}]*\.ax-control,[^}]*font-size:\s*16px;/m)
    expect(form_control_stylesheet).to match(/@media\s*\(prefers-reduced-motion:\s*reduce\)[^{]*\{[^}]*\.ax-control,/m)
    expect(form_control_stylesheet).to match(/data-admin-theme=["']dark["']\] \.ax-input::placeholder/)
    expect(form_control_stylesheet).to match(/data-admin-theme=["']dark["']\] \.ax-select option/)
    expect(form_control_stylesheet).to match(/data-admin-theme=["']dark["']\] \.ax-textarea:disabled/)
    expect(form_control_stylesheet).to match(/data-admin-theme=["']dark["']\] \.ax-input\[readonly\]/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-(?:input|select|textarea)(?:\s*\{|,|:focus)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["']\]\s+\.ax-(?:input|select|textarea)(?:\b|:)/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.automation-workflow-builder \.ax-input/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.habitation-form-ui \.ax-input/)
  end

  it "mantem abas compactas light, dark e responsivas em um componente isolado" do
    expect(form_tabs_stylesheet).to match(/(?:^|\n)\.ax-form-tabs\s*\{/)
    expect(form_tabs_stylesheet).to match(/\.ax-form-tabs__item:focus-visible/)
    expect(form_tabs_stylesheet).to match(/\.ax-form-tabs__item\[aria-selected="true"\]/)
    expect(form_tabs_stylesheet).to match(/\.ax-form-tabs__item:disabled/)
    expect(form_tabs_stylesheet).to include("overscroll-behavior-x: contain", "scrollbar-width: thin")
    expect(form_tabs_stylesheet).to match(/@media \(prefers-reduced-motion: reduce\)[\s\S]*\.ax-form-tabs__item/)
    expect(form_tabs_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-form-tabs\s*\{/)
    expect(form_tabs_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-form-tabs__item\.active/)
    expect(form_tabs_stylesheet).to match(/@media \(max-width: 767\.98px\)[\s\S]*\.ax-form-tabs/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-form-tabs(?:__|\s*\{)/)
    expect(stylesheet).to match(/\.capt-dashboard-tabs \.ax-form-tabs__item/)
    expect(stylesheet).to match(/\.habitation-editor-explorer \.ax-form-tabs__item/)
  end

  it "usa progresso semantico e alturas de rich text sem estilos inline no editor de imovel" do
    expect(habitation_editor_aside_view).not_to match(/\bstyle\s*=/i)
    expect(habitation_editor_aside_view).to include("ax_progress(", "habitation_form_progress_bar: true")
    expect(habitation_form_controller).to include("node.value = percent", 'node.setAttribute("aria-label"')
    expect(habitation_form_controller).not_to include('node.style.width = `${percent}%`')

    source = habitation_rich_text_views.join("\n")
    expect(source).not_to match(/\bstyle\s*=/i)
    expect(source).not_to match(/\bstyle:\s*["']/i)
    expect(habitation_rich_text_views).to all(include("ax-rich-text-control"))
    expect(source.scan("ax-rich-text-control--lg").size).to eq(1)
    expect(habitations_form_stylesheet).to include(".habitation-form-ui .ax-rich-text-control--lg { min-height:250px; }")
    expect(habitations_form_stylesheet).not_to include(".habitation-editor-progress__bar > i")
  end

  it "mantem titulo e subtitulo compactos light e dark isolados" do
    expect(page_heading_stylesheet).to match(/(?:^|\n)\.ax-page-head\s*\{/)
    expect(page_heading_stylesheet).to match(/(?:^|\n)\.ax-page-head__actions\s*\{/)
    expect(page_heading_stylesheet).to match(/(?:^|\n)\.ax-page-title\s*\{/)
    expect(page_heading_stylesheet).to match(/(?:^|\n)\.ax-page-subtitle\s*\{/)
    expect(page_heading_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-page-title/)
    expect(page_heading_stylesheet).to match(/@media \(max-width: 639px\)[^{]*\{[^}]*\.ax-page-head/m)
    expect(page_heading_stylesheet).to include("var(--ax-dark-text)", "var(--ax-dark-text-muted)", "overflow-wrap: anywhere")
    expect(page_heading_stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.ax-page-(?:title|subtitle)[^}]*!important/m)
    expect(page_header_view).to include('class_name].compact.join(" ")', "icon.present?", "ax-page-head__actions", 'role="group" aria-label="Ações da página"')
    expect(page_header_consumer_views).to all(include("ax_page_header("))
    expect(page_heading_stylesheet).not_to include('html[data-admin-theme="dark"]')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-page-(?:head|title|subtitle)(?:__actions)?\s*\{/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["']\]\s+\.ax-page-(?:title|subtitle)\s*\{/)
    expect(property_settings_edit_view).to include("ax_workspace_heading(", 'icon: "building-gear"', 'ax_button(')
    expect(stylesheet).not_to include(".property-settings-header")
    expect(stylesheet).to include(".lead-show-workspace .ax-page-subtitle")
  end

  it "inicializa a previa de marca dagua pelo controller sem estilo inline" do
    expect(property_settings_edit_view).not_to match(/\bstyle\s*=/i)
    expect(property_settings_edit_view).to include("ax_file_field(", "ax_radio_group(", "ax_range_field(")
    expect(property_settings_edit_view).not_to include(
      'class="tab-content"',
      'class="tab-pane',
      'class="property-settings-range"',
      "property-settings-position-option",
      "property-settings-tabs-card"
    )
    expect(property_settings_edit_view).to include('data-watermark-preview-target="frame"')
    expect(property_settings_edit_view).to include('watermark_preview_target: "sizeInput"', 'watermark_preview_target: "opacityInput"')
    expect(watermark_preview_controller).to match(/connect\(\)\s*\{\s*this\.update\(\)/m)
    expect(watermark_preview_controller).to include('style.setProperty("--watermark-size"', 'style.setProperty("--watermark-opacity"')
    expect(stylesheet).to include("width: var(--watermark-size, 28%)", "opacity: var(--watermark-opacity, 1)")
    expect(form_control_stylesheet).to include(
      ".ax-range-field",
      ".ax-range-field__input:focus-visible",
      '[data-admin-theme="dark"] .ax-range-field'
    )
  end

  it "compoe o fluxo de revisao com heading, etapas e footer compartilhados em dark" do
    expect(property_settings_review_workflow_view).to include(
      "ax_workspace_heading(",
      "ax_sticky_action_footer(",
      'ax_workflow(label: "Configuração do fluxo de revisão de captações")',
      '<ol class="ax-workflow__brief"',
      '<li class="ax-workflow__brief-item">'
    )
    expect(property_settings_review_workflow_view).not_to include("<style", "review-workflow-styles", "property_review_workflow", "ax-dashboard-command ax-property-form-command", '<div class="ax-form-actions review-workflow-actions">')
    expect(workflow_stylesheet).to include(
      ".ax-workflow",
      '[data-admin-theme="dark"] .ax-workflow__brief-item',
      '[data-admin-theme="dark"] .ax-workflow__scope',
      "@media (max-width: 640px)"
    )
    ui_helper = File.read(File.expand_path("../../../app/helpers/admin/ui_helper.rb", __dir__))
    workflow_view = File.read(File.expand_path("../../../app/views/admin/shared/ui/_workflow.html.erb", __dir__))
    expect(ui_helper).to include("def ax_workflow(label:", '"admin/shared/ui/workflow"')
    expect(workflow_view).to include('"ax-workflow"', "aria: { label:", "local_assigns[:body]")
  end

  it "organiza a busca inteligente em areas equilibradas e controles dark" do
    expect(property_settings_edit_view).to include(
      'property-settings-ai-panel--search',
      'property-settings-ai-panel--access',
      'property-settings-ai-panel--aliases',
      'property-settings-ai-panel--sharing'
    )
    expect(property_settings_edit_view.scan(/property-settings-sharing-group"/).size).to eq(4)
    expect(property_settings_edit_view.scan(/ax_text_field\(/).size).to be >= 25
    expect(property_settings_edit_view.scan(/ax_number_field\(/).size).to be >= 15
    expect(property_settings_edit_view).to include("ax_select_field(", "ax_standalone_select_field(", "type: :textarea")
    expect(property_settings_edit_view).not_to match(/<label class="ax-field[^>]*>[\s\S]*?<%=\s*f\.(?:text_field|text_area|number_field|select)/)
    expect(property_settings_edit_view).to include(
      'title: "Seleção e validade"',
      'title: "Página pública"',
      'title: "Identificação e lead"',
      'title: "Mensagens operacionais"',
      'ax_inline_notice(tone: :info',
      'label: "Remover alias #{alias_record.name}"'
    )
    expect(stylesheet).to include(
      'grid-template-areas:',
      '"search access"',
      '"search aliases"',
      '"sharing sharing"',
      '.property-settings-sharing-groups { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr));'
    )
    expect(stylesheet).not_to include('html[data-admin-theme="dark"] .property-settings-ai-grid .ax-control')
    expect(form_control_stylesheet).to include(
      '[data-admin-theme="dark"] :where(',
      '.ax-control:not(:disabled):not([readonly]):hover',
      '.ax-control:focus-visible'
    )
    expect(stylesheet).to match(/@media \(max-width: 1100px\)[\s\S]*grid-template-areas: "search" "access" "aliases" "sharing";/)
  end

  it "mantem o cabecalho operacional light, dark e responsivo isolado" do
    expect(workspace_heading_stylesheet).to match(/(?:^|\n)\.ax-workspace-heading\s*\{/)
    expect(workspace_heading_stylesheet).to match(/@media \(max-width: 767\.98px\)[\s\S]*\.ax-workspace-heading__side/)
    expect(workspace_heading_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-workspace-heading\s*\{/)
    expect(workspace_heading_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-workspace-heading__tool:hover/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-workspace-heading(?:__|\s*\{)/)
    expect(stylesheet).to match(/\.wa-inbox-page--focus \.ax-workspace-heading/)
    expect(stylesheet).to match(/\.captacoes-heading \.ax-workspace-heading__toolbar/)
    expect(stylesheet).to match(/\.lead-show-workspace \.ax-workspace-heading/)
  end

  it "mantem botoes e variantes semanticas light e dark isolados" do
    expect(button_stylesheet).to match(/(?:^|\n)\.ax-btn\s*\{/)
    expect(button_stylesheet).to match(/\.ax-btn:disabled,/)
    expect(button_stylesheet).to match(/\.ax-btn--primary\s*\{/)
    expect(button_stylesheet).to match(/\.ax-btn--danger:hover,/)
    expect(button_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-btn--success/)
    expect(button_stylesheet).to include('.ax-btn:not(.ax-btn--primary):not(.ax-btn--danger):not(.ax-btn--success):not(.ax-btn--warning):not(.ax-btn--info):hover')
    expect(button_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-btn:disabled/)
    expect(button_stylesheet).not_to include('html[data-admin-theme="dark"]')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-btn(?:--|\s|:|\[|\.)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["']\]\s+\.ax-btn(?:--|:|\s*\{)/)
    expect(stylesheet).to include(".automation-workflow-new__actions .ax-btn:not(.ax-btn--primary)")
    expect(stylesheet).to include(".habitations-master-content .ax-property-empty .ax-btn")
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-contextbar__button(?:--|\s|:|\[|\.)/)
  end

  it "mantem foco por teclado dos botoes de icone nos dois temas" do
    expect(icon_button_stylesheet).to include(".ax-ico-btn:focus-visible")
    expect(icon_button_stylesheet).to include(".ax-icon-btn:focus-visible")
    expect(icon_button_stylesheet).to include("outline: 2px solid var(--admin-primary-ring)")
    expect(icon_button_stylesheet).to include("box-shadow: 0 0 0 2px var(--admin-primary-ring)")
    expect(icon_button_stylesheet).to include('[data-admin-theme="dark"] :where(.ax-ico-btn, .ax-icon-btn):focus-visible')
    expect(icon_button_stylesheet).to include(':is(:disabled, [aria-disabled="true"], .is-disabled)')
    expect(icon_button_stylesheet).to include("@media (prefers-reduced-motion: reduce)")
    expect(icon_button_stylesheet).not_to include('html[data-admin-theme="dark"]')
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["']\]\s+:where\(\.ax-ico-btn, \.ax-icon-btn\)/)
  end

  it "mantem o shell de modal AX light e dark isolado do Bootstrap" do
    expect(modal_stylesheet).to match(/(?:^|\n)\.ax-modal-overlay\s*\{/)
    expect(modal_stylesheet).to match(/(?:^|\n)\.ax-modal-panel\s*\{/)
    expect(modal_stylesheet).to match(/\.ax-modal-panel__footer\s*\{/)
    expect(modal_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-modal-panel\s*\{/)
    expect(modal_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-modal-panel__header/)
    expect(modal_stylesheet).to include('[data-admin-theme="dark"] .modal-content')
    expect(modal_stylesheet).to include('[data-admin-theme="dark"] .modal-footer')
    expect(modal_stylesheet).to include('[data-admin-theme="dark"] .modal-body')
    expect(modal_stylesheet).to include('[data-admin-theme="dark"] .modal-content .btn-close')
    expect(modal_stylesheet).to include('[data-admin-theme="dark"] .modal-content :where(.card, .list-group-item)')
    expect(modal_stylesheet).to include('.ax-modal-panel__section-header')
    expect(modal_stylesheet).to include('.ax-modal-panel__section-footer')
    expect(modal_stylesheet).to include('[data-admin-theme="dark"] .ax-modal-panel__section-header')
    expect(modal_stylesheet).not_to include('html[data-admin-theme="dark"]')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-modal-(?:overlay|panel)(?:__|\s*\{)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["']\]\s+\.ax-modal-panel/)
    expect(stylesheet).not_to include('html[data-admin-theme="dark"] .modal-content')
    expect(stylesheet).to include(".lead-labels-modal")
  end

  it "mantem foco preso, restaura o acionador e coordena modais empilhados" do
    modal_controller = File.read(File.expand_path("../../../app/javascript/controllers/ax_modal_controller.js", __dir__))

    expect(modal_controller).to include(
      "this.handleKeydown.bind(this)",
      'event.key === "Escape"',
      'event.key !== "Tab"',
      "this.focusableElements()",
      "this.previouslyFocusedElement",
      "this.previouslyFocusedElement.focus()",
      "root.dataset.axModalLockCount",
      "root.dataset.axModalPreviousOverflow",
      "this.scrollLocked",
      'this.overlayTarget.setAttribute("tabindex", "-1")',
      "last.focus()",
      "first.focus()"
    )
  end

  it "aplica cores personalizadas das etiquetas sem estilos inline no servidor" do
    expect(lead_labels_manager_view).not_to match(/\bstyle\s*=/i)
    expect(lead_labels_manager_view).to include('data-label-color="<%= lead_label_css_color(label.color) %>"')
    expect(lead_label_chip_view).not_to include("style:")
    expect(lead_label_chip_view).to include("data: (custom ? { label_color: tone } : {})")
    expect(lead_labels_controller).to include("hydrateCustomColors(document)", '[data-label-color]', '--label-color')
    expect(lead_labels_controller).to match(/\^#\[0-9a-fA-F\]\{6\}\$/)
  end


  it "remove divisores claros inline dos modais operacionais" do
    modal_views = %w[
      appointments/_form_modal.html.erb
      tasks/_form_modal.html.erb
      presentation_cards/_quick_edit_modal.html.erb
      lead_labels/_button.html.erb
    ].map { |path| File.read(File.expand_path("../../../app/views/admin/#{path}", __dir__)) }

    expect(modal_views.join).not_to include('style="border-bottom:1px solid #e6e8eb"')
    expect(modal_views.join).not_to include('style="border-top:1px solid #e6e8eb"')
    expect(modal_views.join).to include('ax-modal-panel__section-header')
    expect(modal_views.join).to include('ax-modal-panel__section-footer')
  end

  it "mantem menus AX light e dark isolados dos dropdowns Bootstrap" do
    expect(menu_stylesheet).to match(/(?:^|\n)\.ax-menu\s*\{/)
    expect(menu_stylesheet).to include(".ax-menu--end", "right: 0", "left: auto")
    expect(menu_stylesheet).to match(/\.is-open > \.ax-menu\s*\{/)
    expect(menu_stylesheet).to match(/\.ax-menu__item--danger:hover/)
    expect(menu_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-menu\s*\{/)
    expect(menu_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-menu__item--danger:hover/)
    expect(menu_stylesheet).to include(".ax-menu__header")
    expect(menu_stylesheet).to include(".ax-menu__item:focus-visible")
    expect(menu_stylesheet).to include('[data-admin-theme="dark"] .dropdown-menu')
    expect(menu_stylesheet).to include('[data-admin-theme="dark"] .dropdown-item.text-danger:focus')
    expect(menu_stylesheet).to include('[data-admin-theme="dark"] .dropdown-header')
    expect(menu_stylesheet).to include('[data-admin-theme="dark"] .dropdown-item.active')
    expect(menu_stylesheet).to include('[data-admin-theme="dark"] .dropdown-item.disabled')
    expect(menu_stylesheet).not_to include('html[data-admin-theme="dark"]')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-menu(?:__|\s*\{)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["']\]\s+\.ax-menu/)
    expect(stylesheet).not_to include('html[data-admin-theme="dark"] .dropdown-menu')
  end

  it "mantem semantica e navegacao por teclado nos menus AX compartilhados" do
    dropdown_controller = File.read(File.expand_path("../../../app/javascript/controllers/ax_dropdown_controller.js", __dir__))

    expect(dropdown_controller).to include(
      'this.triggerTarget.setAttribute("aria-haspopup", "menu")',
      'this.triggerTarget.setAttribute("aria-expanded", "false")',
      'this.triggerTarget.setAttribute("aria-controls", this.menuTarget.id)',
      'this.menuTarget.setAttribute("role", "menu")',
      'item.setAttribute("role", "menuitem")',
      'event.key === "Home"',
      'event.key === "End"',
      'event.key === "ArrowDown"',
      'event.key === "ArrowUp"',
      'this.close({ restoreFocus: true })',
      'this.triggerTarget.focus()'
    )
    expect(dropdown_controller).to include(
      'this.triggerTarget.removeEventListener("keydown", this.onTriggerKeydown)',
      'this.menuTarget.removeEventListener("keydown", this.onMenuKeydown)'
    )
    expect(menu_stylesheet).to include(
      '.ax-menu__item[aria-disabled="true"]',
      '@media (prefers-reduced-motion: reduce)'
    )
  end

  it "mantem botoes da contextbar legiveis em repouso e desabilitados no dark" do
    expect(contextbar_button_stylesheet).to match(/(?:^|\n)\.ax-contextbar__button\s*\{/)
    expect(contextbar_button_stylesheet).to include('.ax-contextbar__button--primary')
    expect(contextbar_button_stylesheet).to include('.ax-contextbar__button--danger')
    expect(contextbar_button_stylesheet).to include('[data-admin-theme="dark"] .ax-contextbar__button:not(.ax-contextbar__button--primary):not(.ax-contextbar__button--danger)')
    expect(contextbar_button_stylesheet).to include('[data-admin-theme="dark"] .ax-contextbar__button:disabled')
    expect(contextbar_button_stylesheet).to include("var(--ax-dark-text-soft)")
    expect(contextbar_button_stylesheet).to include("var(--ax-dark-text-muted)")
    expect(contextbar_button_stylesheet).not_to include('html[data-admin-theme="dark"]')
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["']\]\s+\.ax-contextbar__button/)
  end

  it "mantem dropdowns enriquecidos no mesmo contrato dark dos controles" do
    expect(form_control_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*:where\(\.ts-control, \.ts-dropdown\)/)
    expect(form_control_stylesheet).to include(".ts-dropdown :where(.option, .optgroup-header)")
    expect(form_control_stylesheet).to include(".ts-dropdown :where(.option:hover, .option.active, .option.selected)")
    expect(form_control_stylesheet).to include("var(--ax-dark-placeholder)")
    expect(form_control_stylesheet).to include('[data-admin-theme="dark"] body.ax-habitations-workspace .ts-dropdown')
    expect(form_control_stylesheet).to include('.habitations-inspector .ts-wrapper.disabled .ts-control')
    expect(stylesheet).not_to match(/:where\(\.ax-control, \.ts-control, \.ts-dropdown\)/)
  end

  it "mantem feedbacks compactos dos formularios legiveis no dark" do
    expect(field_feedback_stylesheet).to include('[data-admin-theme="dark"] .habitation-form-ui .ax-field-status')
    expect(field_feedback_stylesheet).to include('.ax-field-status--success')
    expect(field_feedback_stylesheet).to include('.ax-field-status--danger')
    expect(field_feedback_stylesheet).to include('var(--ax-dark-surface-raised)')
  end

  it "mantem superficies internas dos modais de campanha legiveis no dark" do
    expect(stylesheet).to include('html[data-admin-theme="dark"] .whatsapp-sender-modal__advanced')
    expect(stylesheet).to include('html[data-admin-theme="dark"] .whatsapp-sender-card')
    expect(stylesheet).to include('html[data-admin-theme="dark"] .whatsapp-cpl-modal__context')
    expect(stylesheet).to include('html[data-admin-theme="dark"] .whatsapp-cpl-settings__modal')
    expect(stylesheet).to include('html[data-admin-theme="dark"] .whatsapp-cpl-settings__header strong')
  end

  it "mantem conteudo dos modais de SEO e monitoramento legivel no dark" do
    expect(stylesheet).to include('html[data-admin-theme="dark"] .seo-strategy-toggle')
    expect(stylesheet).to include('html[data-admin-theme="dark"] .seo-strategy-toggle:hover')
    expect(stylesheet).to include('html[data-admin-theme="dark"] .automation-workflow-monitor__panel')
    expect(stylesheet).to include('html[data-admin-theme="dark"] .automation-workflow-monitor__header h2')
    expect(stylesheet).to include('html[data-admin-theme="dark"] .automation-workflow-monitor__notice')
  end

  it "mantem os resumos dos modais de imoveis sem cores claras inline" do
    view = File.read(File.expand_path("../../../app/views/admin/habitations/index.html.erb", __dir__))
    expect(view).to include('class="habitations-export-fields__heading')
    expect(view).to include('class="bulk-publish-summary')
    expect(view).not_to include('style="background:#f6f8fb;padding:12px"')
    expect(view).not_to include('style="color:#1f2733" data-bulk-publish-target')
    expect(habitations_catalog_stylesheet).to include('html[data-admin-theme="dark"] .habitations-export-fields__heading')
    expect(habitations_catalog_stylesheet).to include('html[data-admin-theme="dark"] .bulk-publish-summary')
  end

  it "compoe a exportacao de imoveis sem estilos inline no servidor ou no polling" do
    view = File.read(File.expand_path("../../../app/views/admin/habitations/index.html.erb", __dir__))
    export_section = view[/<%# Modal de Exportação.*?<div class="habitations-results-shell">/m]

    expect(export_section).not_to be_nil
    expect(export_section).not_to be_empty
    expect(export_section).not_to match(/\bstyle\s*=/i)
    expect(export_section).to include("ax_progress(", 'habitation_export_target: "progressBar"')
    expect(export_section).to include("habitations-export-recent-item__filename", "habitations-export-fields__list")
    expect(habitation_export_controller).not_to include("style=")
    expect(habitation_export_controller).not_to include("style.width")
    expect(habitation_export_controller).to include("habitations-export-recent-item__filename", "this.progressBarTarget.value = progress")
    expect(habitations_catalog_stylesheet).to include(".habitations-export-modal__history", ".habitations-export-fields__option")
  end

  it "compoe a divulgacao em lote sem estilos inline ou spinner Bootstrap" do
    view = File.read(File.expand_path("../../../app/views/admin/habitations/index.html.erb", __dir__))
    bulk_section = view[/<!-- Bulk Publish Modal -->.*?<\/div><!-- \/\.habitations-results-shell -->/m]

    expect(bulk_section).not_to be_nil
    expect(bulk_section).not_to be_empty
    expect(bulk_section).not_to match(/\bstyle\s*=/i)
    expect(bulk_section.scan("bulk-publish-channel-options").size).to eq(5)
    expect(bulk_section).to include("bulk-publish-modal__accent", "bulk-publish-summary")
    expect(bulk_publish_controller).to include('class="ax-spinner"')
    expect(bulk_publish_controller).not_to include("spinner-border")
    expect(habitations_catalog_stylesheet).to include(".bulk-publish-channel-options", ".bulk-publish-modal__accent")
    expect(habitations_catalog_stylesheet).to include('html[data-admin-theme="dark"] .bulk-publish-modal__accent')
  end


  it "carrega o contrato dark do modal de midia depois do refresh do formulario" do
    layout = File.read(File.expand_path("../../../app/views/layouts/admin.html.erb", __dir__))
    expect(layout.index('stylesheet_link_tag "admin/components/media_modal"')).to be > layout.index('stylesheet_link_tag "habitations_form_refresh"')
    expect(media_modal_stylesheet).to include('[data-admin-theme="dark"] .ax-media-modal__panel')
    expect(media_modal_stylesheet).to include('[data-admin-theme="dark"] .ax-media-modal__body')
    expect(media_modal_stylesheet).to include('[data-admin-theme="dark"] .ax-media-modal__form')
    expect(media_modal_stylesheet).to include('[data-admin-theme="dark"] .ax-media-modal__actions .ax-icon-btn')
    expect(media_modal_stylesheet).to include('[data-admin-theme="dark"] .ax-media-modal__footer .ax-btn:not(.ax-btn--primary)')
    expect(media_modal_stylesheet).not_to include('html[data-admin-theme="dark"]')
    expect(media_modal_stylesheet).to include("var(--ax-dark-text-muted)")
  end

  it "mantem os dois contratos historicos de botao de icone sem fundir sua geometria" do
    expect(icon_button_stylesheet).to match(/(?:^|\n)\.ax-ico-btn\s*\{/)
    expect(icon_button_stylesheet).to match(/(?:^|\n)\.ax-icon-btn\s*\{/)
    expect(icon_button_stylesheet).to include("border-radius: 6px")
    expect(icon_button_stylesheet).to include("border-radius: 7px")
    expect(icon_button_stylesheet).to match(/data-admin-theme=["']dark["']\] \.ax-ico-btn\s*\{[^}]*background:\s*transparent/m)
    expect(icon_button_stylesheet).to match(/data-admin-theme=["']dark["']\] \.ax-icon-btn\s*\{[^}]*background:\s*var\(--ax-dark-surface-raised\)/m)
    expect(icon_button_stylesheet).to include(".ax-ico-btn:active", ".ax-icon-btn:active")
    expect(icon_button_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-ico-btn[^)]*\.ax-icon-btn[^)]*\):hover/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-(?:ico-btn|icon-btn)\s*\{/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*:where\(\.ax-ico-btn, \.ax-icon-btn\)/)
    expect(stylesheet).to include(".distribution-rules-index__table .ax-table tbody tr:hover .ax-ico-btn")
  end

  it "mantem spinner e preloader global isolados com acessibilidade de movimento" do
    admin_layout = File.read(File.expand_path("../../../app/views/layouts/admin.html.erb", __dir__))

    expect(loading_stylesheet).to match(/(?:^|\n)\.ax-spinner\s*\{/)
    expect(loading_stylesheet).to include("@keyframes ax-spin")
    expect(loading_stylesheet).to match(/\.ax-admin-preloader\[hidden\]\s*\{/)
    expect(loading_stylesheet).to match(/\.ax-admin-preloader\.is-visible\s*\{/)
    expect(loading_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-admin-preloader\s*\{/)
    expect(loading_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-admin-preloader\.has-rendered/)
    expect(loading_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-admin-preloader__panel\s*\{/)
    expect(loading_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-admin-preloader__spinner\s*\{/)
    expect(loading_stylesheet).to include("var(--ax-dark-workspace)")
    expect(loading_stylesheet).to include("var(--ax-dark-surface-raised)")
    expect(loading_stylesheet).to include("html.ax-admin-is-loading body.ax-app .ax-main")
    expect(loading_stylesheet).to include("@media (prefers-reduced-motion: reduce)")
    expect(loading_stylesheet).to match(/prefers-reduced-motion:[^{]*reduce[^}]*\}\s*\.ax-spinner,[^{]*\.ax-admin-preloader__spinner,[^{]*\.ax-skeleton-pill::after/m)
    expect(loading_stylesheet).to match(/\.ax-admin-preloader__spinner,[^{]*\.ax-skeleton-pill::after[^{]*\{[^}]*animation:\s*none/m)
    expect(loading_stylesheet).not_to include('html[data-admin-theme="dark"]')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-spinner\s*\{/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-admin-preloader(?:__|\.|\[|\s*\{)/)
    expect(admin_layout).to include('class="ax-admin-preloader"')
    expect(admin_layout).to include('class="ax-admin-preloader__spinner"')
  end

  it "nao devolve upload e lista de arquivos para overrides exclusivos do formulario de imovel" do
    expect(stylesheet).not_to match(
      /\[data-admin-theme=["']dark["']\]\s+\.habitation-form-ui\s+\.(?:ax-upload-(?:control|button|status)|ax-file-list__(?:item|title|meta))\b/
    )
  end

  it "mantem input, select e textarea com os mesmos estados interativos no dark" do
    expect(form_control_stylesheet).to match(/\[data-admin-theme=["']dark["']\] \.ax-select:focus/)
    expect(form_control_stylesheet).to match(/\[data-admin-theme=["']dark["']\] \.ax-textarea:disabled/)
    expect(form_control_stylesheet).to match(/\[data-admin-theme=["']dark["']\] \.ax-textarea::placeholder/)
  end

  it "mantem toggle chip compartilhado, inclusive no formulario de imovel" do
    expect(toggle_chip_stylesheet).to match(/(?:^|\n)\.ax-toggle-chip\s*\{/)
    expect(toggle_chip_stylesheet).to match(/\.ax-toggle-chip__input:checked/)
    expect(toggle_chip_stylesheet).to match(/\.ax-toggle-chip:has\(\.ax-toggle-chip__input:checked\)/)
    expect(toggle_chip_stylesheet).to match(/\.ax-toggle-chip\.is-checked:hover/)
    expect(toggle_chip_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-toggle-chip:has\(\.ax-toggle-chip__input:checked\)/)
    expect(toggle_chip_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-chip-grid \.ax-toggle-chip__input:not\(:checked\)/)
    expect(toggle_chip_stylesheet).to match(/\.ax-chip-grid \.ax-toggle-chip__input:not\(:checked\)[^{]*\{[^}]*background-image:\s*none\s*!important/m)
    expect(toggle_chip_stylesheet).to match(/\.ax-toggle-chip:has\(\.ax-toggle-chip__input:disabled:not\(:checked\)\)/)
    expect(toggle_chip_stylesheet).to match(/@media\s*\(max-width:\s*639px\)/)
    expect(toggle_chip_stylesheet).to match(/@media\s*\(prefers-reduced-motion:\s*reduce\)/)
    expect(toggle_chip_view).to include('data-checked="<%= checked_state %>"', 'aria-disabled="<%= disabled %>"', '("is-disabled" if disabled)')
    expect(checkbox_chips_controller).to include("disconnect()", "cancelAnimationFrame(this.syncFrame)", 'chip.classList.toggle("is-disabled"', 'chip.setAttribute("aria-disabled", "true")', "chip.dataset.checked")
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-toggle-(?:chip|group)(?:__|--|\s|\.)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.ax-toggle-chip/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.habitation-form-ui\s+\.ax-toggle-chip\b/)
  end

  it "mantem radio groups light e dark globais com compatibilidade do editor" do
    expect(radio_group_stylesheet).to match(/(?:^|\n)\.ax-radio-group\s*\{/)
    expect(radio_group_stylesheet).to match(/\.ax-radio-group__item:has\(\.ax-radio-group__input:checked\)/)
    expect(radio_group_stylesheet).to match(/\.ax-radio-group__item:hover/)
    expect(radio_group_stylesheet).to match(/\.ax-radio-group__item:has\(\.ax-radio-group__input:focus-visible\)/)
    expect(radio_group_stylesheet).to match(/\.ax-radio-group__item:has\(\.ax-radio-group__input:disabled\)/)
    expect(radio_group_stylesheet).to match(/@media\s*\(max-width:\s*639px\)/)
    expect(radio_group_stylesheet).to match(/@media\s*\(prefers-reduced-motion:\s*reduce\)/)
    expect(radio_group_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-radio-group__item\s*\{/)
    expect(radio_group_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-radio-group__item:hover/)
    expect(radio_group_view).to include('<fieldset class="<%= group_classes %>">', '<legend class="ax-radio-group__label">', "disabled: disabled")
    expect(radio_group_view).not_to include('role="radiogroup"', "aria-label=")
    expect(stylesheet).not_to match(/(?:^|\n)\.habitation-form-ui \.ax-radio-group(?:__|\s|\+)/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.habitation-form-ui \.ax-radio-group__item/)
  end

  it "mantem os tiles exclusivos de midia escuros sem globalizar sua estrutura" do
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.habitation-form-ui\s+\.ax-media-tile__frame\b/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.habitation-form-ui\s+\.ax-media-action--danger\b/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["']\s+\.ax-media-tile__frame\b/)
    expect(stylesheet).to match(/\.habitation-form-ui \.media-photo-site-toggle\s*\{[^}]*width:\s*26px\s*!important;[^}]*min-width:\s*26px;[^}]*overflow:\s*hidden;/m)
    expect(habitation_media_gallery_view).to include('aria-pressed="<%= !photo_hidden_from_site %>"')
    expect(habitation_media_gallery_view).to include('aria-pressed="<%= !picture_hidden_from_site %>"')
    expect(habitation_media_gallery_view).not_to include('<span><%= photo_hidden_from_site', '<span><%= picture_hidden_from_site')
    expect(photo_upload_controller).to include('button.setAttribute(\'aria-pressed\', hidden ? \'false\' : \'true\')')
    expect(photo_upload_controller).not_to include("button.querySelector('span')")
  end

  it "mantem as superficies dos templates de WhatsApp dentro do seu workspace dark" do
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.whatsapp-templates[^{]*\.whatsapp-template-header/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.whatsapp-templates[^{]*\.whatsapp-template-table th/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.whatsapp-templates[^{]*\.whatsapp-template-phone-preview/)
  end

  it "mantem o gerenciador compartilhado de atributos integralmente no contrato dark" do
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-attribute-modal__panel/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-attribute-list__item/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-attribute-list__mini-btn--danger/)
  end

  it "mantem cards de tarefas administrativas no contrato dark compartilhado" do
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-builder-card\b/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-builder-card[^{]*\.ax-builder-panel-head/)
  end

  it "mantem cards, tabela e seletor de visualizacao de imoveis no contrato dark" do
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-property-card\b/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-property-card__features span/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-property-table-wrap\b/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-property-table tbody tr:hover td/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-property-table__features span/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-columns-picker__row:hover/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.habitations-view-toggle__item\.is-active/)
  end

  it "mantem o seletor de visualizacao generico fora de overrides exclusivos de Leads" do
    expect(view_toggle_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-view-toggle\s*\{/)
    expect(view_toggle_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-view-toggle__item:focus-visible/)
    expect(view_toggle_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-view-toggle__item\.is-active/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.ax-leads-mobile-shell[^{]*\.ax-view-toggle/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-view-toggle(?:__item)?\b/)
  end

  it "mantem a tabela AX completa no contrato dark global" do
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-table thead th/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-table tbody td/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-table tbody tr:nth-child\(even\) td/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-table tbody tr:hover td/)
  end

  it "mantem todos os tons de badge no contrato dark global" do
    %w[gray green amber red blue purple cyan].each do |tone|
      expect(badge_stylesheet).to match(
        /data-admin-theme=["']dark["'][^{]*\.ax-badge--#{tone}\s*\{/
      )
    end

    expect(badge_stylesheet).not_to include('html[data-admin-theme="dark"]')

    expect(admin_ui_helper_source).to include('neutral: "ax-badge--gray"', 'orange: "ax-badge--amber"')
    expect(marketing_campaign_views.first).not_to include('<span class="ax-badge')
    expect(banners_index_view).not_to include('<span class="ax-badge')
    expect(access_audit_logs_view).not_to include('<span class="ax-badge')
    expect([marketing_campaign_views.first, banners_index_view, access_audit_logs_view]).to all(include("ax_badge("))

    expect(stylesheet).not_to match(/(?:^|\n)\.ax-badge(?:--[a-z]+)?\b/)
  end


  it "mantem avatares com imagem e fallback em tamanhos compartilhados" do
    expect(avatar_stylesheet).to match(/(?:^|\n)\.ax-avatar\s*\{/)
    expect(avatar_stylesheet).to match(/\.ax-avatar--xxs\s*\{[^}]*width:\s*22px;[^}]*height:\s*22px;/m)
    expect(avatar_stylesheet).to match(/\.ax-avatar--xs\s*\{[^}]*width:\s*30px;[^}]*height:\s*30px;/m)
    expect(avatar_stylesheet).to match(/\.ax-avatar--sm\s*\{[^}]*width:\s*34px;[^}]*height:\s*34px;/m)
    expect(avatar_stylesheet).to match(/\.ax-avatar--md\s*\{[^}]*width:\s*40px;[^}]*height:\s*40px;/m)
    expect(avatar_stylesheet).to match(/\.ax-avatar--lg\s*\{[^}]*width:\s*48px;[^}]*height:\s*48px;/m)
    expect(avatar_stylesheet).to match(/\.ax-avatar--xl\s*\{[^}]*width:\s*54px;[^}]*height:\s*54px;/m)
    expect(avatar_stylesheet).to match(/\.ax-avatar--xxl\s*\{[^}]*width:\s*76px;[^}]*height:\s*76px;/m)
    expect(avatar_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-avatar\s*\{/)
    expect(avatar_view).to include("image_tag image", 'role="img"', "aria-label=\"<%= name %>\"", "<%= initials %>")
    expect(avatar_consumer_views).to all(include("ax_avatar("))
    expect(avatar_consumer_views.first(3).join).not_to match(/(?:au-user|aus|hier-row)__(?:img|initial)/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-avatar(?:--[a-z]+)?\b/)
  end


  it "reutiliza o avatar compartilhado na topbar e no formulario de usuario" do
    admin_layout = File.read(File.expand_path("../../../app/views/layouts/admin.html.erb", __dir__))
    admin_user_form = File.read(File.expand_path("../../../app/views/admin/admin_users/_form.html.erb", __dir__))
    admin_user_form_styles = File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/admin_user_form.css", __dir__))

    expect(admin_layout).to include("ax_avatar(", "size: :xxs", 'class_name: "ax-navbar__avatar"')
    expect(admin_user_form).to include("ax_avatar(", "size: :xxl")
    expect(admin_user_form).not_to include("au-avatar__img", "au-avatar__placeholder")
    expect(admin_user_form_styles).not_to include(".au-avatar__img", ".au-avatar__placeholder")
    expect(stylesheet).to include(".ax-navbar__avatar:not(.ax-avatar)")
  end

  it "mantem o cartao compartilhado de compromissos responsivo e compativel com dark theme" do
    expect(appointment_card_stylesheet).to match(/(?:^|\n)\.ax-appointment-grid\s*\{/)
    expect(appointment_card_stylesheet).to match(/(?:^|\n)\.ax-appointment-card\s*\{/)
    expect(appointment_card_stylesheet).to match(/\.ax-appointment-card\.is-cancelled\s*\{[^}]*border-style:\s*dashed;/m)
    expect(appointment_card_stylesheet).to match(/\.ax-appointment-card\.is-completed\s*\{[^}]*border-left:/m)
    expect(appointment_card_stylesheet).not_to match(/\.ax-appointment-card\.is-cancelled\s*\{[^}]*opacity:/m)
    expect(appointment_card_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-appointment-card\s*\{/)
    expect(appointment_card_stylesheet).to match(/\.ax-appointment-card:focus-within/)
    expect(appointment_card_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-appointment-card:hover/)
    expect(appointment_card_stylesheet).to match(/@media\s*\(max-width:\s*767\.98px\)[\s\S]*\.ax-appointment-grid/)
    expect(appointment_card_stylesheet).to match(/@media \(prefers-reduced-motion: reduce\)/)
    expect(appointment_card_view).not_to match(/\bstyle\s*=/i)
    expect(appointment_card_view).to include("appointment.starts_at.iso8601", "appointment.lead.display_name", "can?(:manage, :comercial)", 'status: "realizado"', 'turbo_confirm: "Remover compromisso?"')
    expect(appointment_card_view).to include('"realizado" => ["Realizado", "green"]', '"cancelado" => ["Cancelado", "red"]')
    expect(appointment_card_view).to include('aria: { label: "Marcar compromisso como realizado" }', 'aria: { label: "Remover compromisso" }')
    expect(appointment_card_view.scan("ax-btn--icon").size).to eq(2)
  end

  it "mantem o formulario e apoios de usuarios sem CSS embutido ou geometria inline" do
    admin_users_index_view = File.read(File.expand_path("../../../app/views/admin/admin_users/index.html.erb", __dir__))

    expect(admin_user_form_view).not_to match(/<style\b/i)
    expect(admin_user_form_view).not_to match(/\bstyle\s*=/i)
    expect(admin_user_form_view).to include(
      "ax_file_field(",
      "ax_text_field(",
      "ax_date_field(",
      "ax_select_field(",
      "ax_standalone_select_field(",
      "ax_chip_grid do",
      "ax_status_list("
    )
    expect(admin_user_form_view).not_to match(/\bf\.(?:text_field|email_field|file_field|date_field|text_area|password_field|select|collection_select)\b/)
    expect(admin_users_index_view).not_to match(/<style\b|\bstyle\s*=/i)
    expect(admin_users_index_view).to include(
      "ax_workspace_heading(",
      "ax_filter_form(",
      'ax_icon_button(label: "Editar usuário #{user.name}"',
      'label: "Excluir usuário #{user.name}"',
      "ax_standalone_select_field(",
      "ax_form_actions(sticky: false)"
    )
    expect(admin_users_index_view).not_to include("ax-dashboard-command ax-property-form-command", 'class="au-filters"', 'class="ax-ico-btn"')
    expect(admin_user_form_stylesheet).to match(/(?:^|\n)\.au-form\s*\{/)
    expect(admin_user_form_stylesheet).to match(/(?:^|\n)\.au-page\s*\{/)
    expect(admin_user_form_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.au-page/)
    expect(admin_user_form_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.au-form/)
    expect(admin_user_form_stylesheet).to include(".au-avatar-row__field", "@media (min-width: 1080px)", "@media (max-width: 560px)")
    expect(admin_user_form_stylesheet).not_to include(".au-filters", ".reassign-delete__actions", ".au-field", ".au-hint", ".au-row", ".au-switches")
    expect(admin_user_form_stylesheet).not_to include('[data-admin-theme="dark"] .au-form :where(input, select, textarea)')
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.au-page/)

    support_source = admin_user_support_views.join("\n")
    expect(support_source).not_to match(/\bstyle\s*=/i)
    expect(support_source.scan(/ax_progress\(/).size).to eq(2)
    expect(support_source).to include("hier-row__handle is-placeholder", "ax-table__col--w-130")
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.au-form/)
  end

  it "adota os contratos compartilhados nas visoes da Agenda" do
    expect(appointments_index_view).not_to match(/\bstyle\s*=/i)
    expect(appointments_index_view).to include("ax_workspace_heading(", 'class="ax-appointment-grid"', "ax_appointment_card(appointment: appt)", "ax_appointment_card(appointment: appt, expanded: true)", "ax_empty_state(")
    expect(appointments_index_view).to include('semana', 'dia', 'lista', 'form_modal', 'ax_team_toggle(:comercial)')
  end

  it "mantem dicas dispensaveis compartilhadas, seguras e compativeis com dark theme" do
    expect(dismissible_hint_stylesheet).to match(/(?:^|\n)\.ax-dismissible-hint\s*\{/)
    expect(dismissible_hint_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-dismissible-hint\s*\{/)
    expect(dismissible_hint_stylesheet).to match(/@media\s*\(max-width:\s*767\.98px\)[\s\S]*\.ax-dismissible-hint__body/)
    expect(dismissible_hint_stylesheet).to match(/\.ax-dismissible-hint\[hidden\]/)
    expect(dismissible_hint_stylesheet).to match(/\.ax-dismissible-hint\.is-dismissing/)
    expect(dismissible_hint_stylesheet).to match(/\.ax-dismissible-hint__dismiss:focus-visible/)
    expect(dismissible_hint_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-dismissible-hint__dismiss:focus-visible/)
    expect(dismissible_hint_stylesheet).to match(/@media\s*\(prefers-reduced-motion:\s*reduce\)/)
    expect(dismissible_hint_view).not_to match(/\bstyle\s*=/i)
    expect(dismissible_hint_view).not_to include("html_safe")
    expect(dismissible_hint_view).to include("sanitize(text", 'data-controller="dismissible"', 'data-action="dismissible#dismiss"', 'data-dismissible-key-value="<%= key %>"', "data-dismissible-storage-key-value")
    expect(dismissible_hint_view).to include('role="note"', 'aria-label="Dica"', 'aria-controls="<%= hint_id %>"')
    expect(dismissible_controller).to include("this.element.hidden", "syncAccessibleState", 'this.dispatch("dismissed"', "adjacentFocusTarget", "focusTarget.focus()")
    expect(dismissible_controller).to include('prefers-reduced-motion: reduce', 'this.element.setAttribute("aria-hidden", "true")')
    expect(dismissible_controller).to include("get storageIdentifier()", "this.hasStorageKeyValue ? this.storageKeyValue : this.keyValue")
    expect(dismissible_controller).to include(%q(element.closest("[hidden], [aria-hidden='true'], [inert]")))
    expect(File.read(File.expand_path("../../../app/helpers/admin/ui_helper.rb", __dir__))).to include(%q(storage_scope = "admin-user-#{current_admin_user&.id || 'anonymous'}"))
    expect(dismissible_controller).not_to include("style.display")
    expect(dismissible_hint_consumers.join).not_to include('admin/shared/hint')
    expect(dismissible_hint_consumers.sum { |view| view.scan(/ax_dismissible_hint\(/).size }).to eq(3)
  end


  it "usa os contratos compartilhados nos resumos, filtros e tabelas operacionais do WhatsApp" do
    audience_stylesheet = File.read(
      File.expand_path("../../../app/assets/stylesheets/admin/components/audience_workspace.css", __dir__)
    )

    [whatsapp_campaign_recipients_view, whatsapp_campaign_unsubscribes_view].each do |view|
      expect(view).to include('class="ax-metric-grid')
      expect(view).to include("ax_metric_card")
      expect(view).to include('class: "ax-card')
      expect(view).to include('class="ax-table-wrap"')
      expect(view).to include('class="ax-audience-workspace"')
      expect(view).not_to match(/background:\s*#fff/i)
    end

    expect(audience_stylesheet).to match(
      /data-admin-theme=["']dark["'][^{]*:where\([^)]*ax-audience-workspace__reason/
    )
  end

  it "usa o preview de midia compartilhado no cadastro e detalhe dos banners" do
    source = banner_views.join

    expect(source).not_to match(/\bstyle\s*=/i)
    expect(source.scan(/ax_media_preview\(/).size).to eq(4)
    expect(source.scan(/ax_operational_panel\(/).size).to eq(4)
    expect(source).to include('class="ax-media-preview-grid')
    expect(source).not_to include("preview-container", "preview-desktop", "preview-mobile")
    expect(media_preview_stylesheet).to match(/\.ax-media-preview-grid\s*\{/)
    expect(media_preview_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-media-preview__frame\s*\{[^}]*background:\s*var\(--ax-dark-surface-raised\)/m)
    expect(media_preview_stylesheet).to match(/@media \(max-width:\s*760px\)/)
    expect(stylesheet).not_to match(/\.preview-(?:container|box|label|image-wrapper)\b/)
  end

  it "reutiliza o preview como thumbnail e o estado vazio na listagem de banners" do
    expect(banners_index_view).not_to match(/\bstyle\s*=/i)
    expect(banners_index_view).to include("ax_media_preview(", "size: :thumbnail", "ax_empty_state(")
    expect(banners_index_view).to include("ax-table__col--md", "ax-table__col--w-220", "ax-table__col--w-80", "ax-table__col--sm", "ax-table__col--compact")
    expect(media_preview_stylesheet).to match(/\.ax-media-preview--thumbnail \.ax-media-preview__frame,[^{]*\{[^}]*width:\s*88px;[^}]*height:\s*50px;/m)
    expect(table_stylesheet).to include(".ax-table__col--w-220")
  end

  it "usa metric cards compartilhados no resumo da listagem de leads" do
    expect(leads_index_view).to include('class="ax-metric-grid lead-list-summary"')
    expect(leads_index_view.scan("ax_metric_card").size).to eq(4)
    expect(leads_index_view).to include('ax_badge("Entrada", tone: :amber)')
    expect(leads_index_view).to include('ax_badge("Atenção", tone: :red)')
    expect(leads_index_view).not_to include("lead-list-summary__item")
    expect(stylesheet).not_to include("lead-list-summary__item")
  end

  it "usa metric cards compartilhados na listagem e no dashboard de captacoes" do
    index_view, dashboard_view = captacoes_metric_views

    expect(index_view).not_to match(/\bstyle\s*=/i)
    expect(index_view).to include('class="ax-metric-grid captacoes-kpi-strip"')
    expect(index_view).to include('ax_metric_card(label:, value:, class_name: "captacoes-kpi')
    expect(index_view).to include("ax-table__col--compact", "ax-table__col--sm", "ax-table__col--md")
    expect(index_view).to include("ax-table__col--w-120", "ax-table__col--w-130", "ax-table__col--w-150")
    expect(dashboard_view).to include('class="ax-metric-grid capt-dashboard-kpis"')
    expect(dashboard_view).to include('ax_metric_card(label:, value:, class_name: "capt-dashboard-kpi')
    expect(stylesheet).not_to match(/\.capt(?:acoes|\-dashboard)-kpi\s*\{[^}]*background:\s*#fff/m)
    expect(stylesheet).not_to match(/\.captacoes-kpi__(?:label|value)/)
    expect(stylesheet).to include(".captacoes-kpi .ax-metric-card__value")
    expect(stylesheet).to include(".capt-dashboard-kpi .ax-metric-card__value")
  end

  it "padroniza filtros, acoes iconicas e estados vazios da listagem de captacoes" do
    expect(captacoes_index_view).to include("hidden_field_tag :team, params[:team]", "admin_captacoes_path(team: params[:team])")
    expect(captacoes_index_view).to include('for="property_kind"', 'for="status"', 'for="corretor_id"')
    expect(captacoes_index_view.scan(/ax_empty_state\(/).size).to eq(2)
    expect(captacoes_index_view.scan(/ax_icon_button label:/).size).to eq(2)
    expect(captacoes_index_view).to include('label: "Ver captação #{c.display_title}"', 'label: "Continuar captação #{c.display_title}"')
    expect(captacoes_index_view).not_to include('class="ax-empty"', "captacoes-empty-state")
    expect(stylesheet).not_to include(".captacoes-empty-state")
  end

  it "mantem ranking e heatmap de captacoes sem geometria inline" do
    expect(captacoes_ranking_table_view).not_to match(/\bstyle\s*=/i)
    expect(captacoes_ranking_table_view).to include('class="ax-table__col--w-40"', 'class="capt-ranking-table__col-chart"', 'class="bar-cell"')
    expect(captacoes_ranking_table_view).to include("ax_progress(", 'class_name: "capt-ranking-row__progress"', 'label: "#{row.name}: #{row.ct} captações"')
    expect(stylesheet).to include(".capt-ranking-row__progress.ax-progress", "color: var(--capt-dark-text) !important")
    expect(captacoes_ranking_table_view).to include("rows.each_with_index", "number_to_currency(row.total_value.to_f", "Sem dados no período")
    expect(stylesheet).to match(/\.capt-ranking-table__col-chart\s*\{[^}]*min-width:\s*140px;/m)
    expect(stylesheet).to match(/\.capt-ranking-row \.bar-cell\s*\{[^}]*width:\s*100%;/m)

    expect(captacoes_leads_heatmap_view).not_to match(/\bstyle\s*=/i)
    expect(captacoes_leads_heatmap_view).to include("intensity_level", 'hc hc--intensity-<%= intensity_level %>')
    expect(captacoes_leads_heatmap_view).not_to include("alpha", "rgba(")
    (1..5).each do |level|
      expect(stylesheet).to include(".heatmap-table td.hc--intensity-#{level}")
      expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.heatmap-table td\.hc--intensity-#{level}/)
    end
  end

  it "compartilha a grade de definicoes entre detalhe e revisao da captacao" do
    show_view, review_view = captacao_review_views
    combined_view = captacao_review_views.join("\n")

    expect(combined_view).not_to match(/\bstyle\s*=/i)
    expect(show_view.scan("capt-detail-definition-grid").size).to eq(4)
    expect(review_view.scan("capt-detail-definition-grid").size).to eq(3)
    expect(show_view).to include("ax-table__col--compact", "capt-detail-change-arrow")
    expect(review_view).to include("wizard-review-title-icon", "wizard-photo-grid")
    expect(show_view).to include("approve_admin_captacao_path", "return_to_broker_admin_captacao_path", "release_to_site_admin_captacao_path")
    expect(review_view).to include("review_layer_enabled", "@captacao.fotos.first(6)")
    expect(stylesheet).to include(".capt-detail-definition-grid", ".capt-detail-change-arrow", ".wizard-photo-grid")
    expect(stylesheet).to include('html[data-admin-theme="dark"] .wizard-review-title-icon')
  end

  it "mantem cadastro e etapas da captacao sem geometria inline e com progresso compartilhado" do
    source = captacao_wizard_views.join("\n")
    migrated_step_sources = %w[_proprietario _endereco _infraestrutura _visitas _intro _negociacao _fotos _caracteristicas].index_with do |partial|
      File.read(File.expand_path("../../../app/views/admin/captacoes/steps/#{partial}.html.erb", __dir__))
    end

    expect(source).not_to match(/\bstyle\s*=/i)
    expect(source).not_to match(/\bstyle:\s*["']/i)
    expect(source).not_to include("wizard-progress-bar")
    expect(source.scan(/ax_progress\(/).size).to eq(2)
    expect(source).to include("wizard-top-bar__summary", "wizard-nav-action")
    expect(migrated_step_sources.values.join("\n")).to include("ax_text_field(", "ax_select_field(", "ax_number_field(", "ax_currency_field(", "ax_standalone_field(")
    direct_control_pattern = /f\.(?:label|text_field|email_field|telephone_field|number_field|datetime_local_field|select|text_area)/
    expect(migrated_step_sources.except("_endereco").values).to all(satisfy { |source| !source.match?(direct_control_pattern) })
    expect(migrated_step_sources.fetch("_endereco").scan(/f\.text_field/).size).to eq(1)
    expect(migrated_step_sources.fetch("_endereco").scan(/f\.label/).size).to eq(0)
    expect(migrated_step_sources.fetch("_fotos")).to include('type: :"datetime-local"', "ax_file_upload_button(")
    expect(captacao_wizard_stylesheet).to include(".wizard-top-bar__summary", ".wizard-nav-action", ".wizard-progress.ax-progress")
    expect(captacao_wizard_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.wizard-progress/)
    expect(captacao_wizard_layout).to include('stylesheet_link_tag "admin/captacao_wizard"')
    expect(captacao_wizard_layout).not_to include(".wizard-progress-bar")
  end

  it "compoe secoes da Home com chips, registros e preview compartilhados sem inline" do
    source = home_section_workspace_views.join("\n")

    expect(source).not_to match(/\bstyle\s*=/i)
    expect(source).not_to match(/\bstyle:\s*["']/i)
    expect(source).to include("ax_record_item(", "ax_chip_grid do", "ax_toggle_chip(", "ax_media_preview(")
    expect(source).to include('include_hidden: false', 'variant: :thumbnail')
    expect(chip_grid_view).not_to include("style:")
    expect(toggle_chip_stylesheet).to match(/(?:^|\n)\.ax-chip-grid\s*\{[^}]*grid-template-columns:/m)
    expect(toggle_chip_stylesheet).to include(".ax-chip-grid .ax-toggle-chip__input:checked")
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-chip-grid\s*\{/)
  end

  it "compoe o editor visual da Home com cores compartilhadas sem estilos inline" do
    expect(home_settings_edit_view.scan(/ax_color_field\(/).size).to eq(7)
    expect(home_settings_edit_view).not_to match(/\bstyle\s*=/i)
    expect(home_settings_edit_view).not_to include("style:")
    expect(home_settings_edit_view).to include('data-home-settings-preview-target="overlayPreview"')
    expect(home_settings_edit_view).to include('home_settings_preview_target: "overlayColorPicker"', 'home_settings_preview_target: "overlayColorText"')
    expect(home_settings_edit_view).to include('input->home-settings-preview#syncPair', 'input->home-settings-preview#syncOverlay')
    expect(home_settings_preview_controller).to match(/connect\(\)\s*\{\s*this\.updateOverlay\(\)/m)
    expect(home_settings_preview_controller).to include("style.backgroundColor = color", "style.opacity = opacity")
    expect(home_settings_edit_view).to include("home-settings-card--fill", "home-settings-slide-thumb__image", "home-settings-mobile-preview")
    expect(home_settings_edit_view).to include("ax_operational_panel(", "ax_field_group(", "ax_file_field(", "ax_number_field(", "ax_measure_field(")
    expect(home_settings_edit_view).not_to match(/\b(tab-content|tab-pane|position-relative|position-absolute|img-fluid|alert-link)\b/)
    expect(stylesheet).to include(".home-settings-overlay-preview", "html[data-admin-theme=\"dark\"] .home-settings-remove-label")
  end

  it "mantem o editor de layout tokenizado sem estilos inline" do
    menu_keys = %w[product operation management growth public-site integrations settings account]
    theme_swatches = %w[surface header workspace sidebar primary ink]

    expect(layout_settings_edit_view).not_to match(/\bstyle\s*=/i)
    expect(layout_settings_edit_view).to include("data-layout-theme-preview-initial-surface", "data-layout-theme-preview-public-primary", "token_contract[:theme_var]")
    expect(layout_settings_edit_view).to include('data-theme-swatch="<%= token_contract[:theme_var].delete_prefix("--theme-") %>"')
    expect(layout_settings_edit_view).not_to include('style="background:#111827"', 'style="background:<%= public_primary %>"', 'style="background:<%= admin_primary %>"')
    expect(layout_theme_preview_controller).to include("applyInitialTheme()", "INITIAL_THEME_DATASET", '--theme-public-primary')

    menu_keys.each do |key|
      expect(layout_settings_edit_view).to include(%(data-menu-section-preview="<%= css_key %>"))
      expect(stylesheet).to include(%(.layout-settings-menu-style-preview[data-menu-section-preview="#{key}"]))
    end

    theme_swatches.each do |token|
      expect(layout_settings_edit_view).to include(%(data-theme-swatch="#{token}"))
      expect(stylesheet).to include(%([data-theme-swatch="#{token}"]))
    end

    expect(layout_settings_edit_view).to include("layout-settings-impact__swatch--platform", "layout-settings-impact__swatch--public", "layout-settings-impact__swatch--admin")
    expect(stylesheet).to include(".layout-settings-impact__swatch--public", "background: var(--theme-public-primary)")
  end

  it "padroniza as linhas aninhadas do rodape sem Bootstrap ou estilos inline" do
    edit_view, *nested_views = footer_settings_views
    combined_nested_views = nested_views.join("\n")

    expect(footer_settings_views.join("\n")).not_to match(/\bstyle\s*=/i)
    expect(footer_settings_views.join("\n")).not_to include("style:")
    expect(combined_nested_views).not_to include('class="col-12 nested-fields"', 'class="ax-card bg-light"')
    expect(combined_nested_views.scan("footer-nested-field").size).to eq(3)
    expect(combined_nested_views.scan("footer-nested-position").size).to eq(3)
    expect(combined_nested_views.scan('data-action="nested-form#moveUp"').size).to eq(3)
    expect(combined_nested_views.scan('data-action="nested-form#moveDown"').size).to eq(3)
    expect(combined_nested_views.scan('data-action="nested-form#remove"').size).to eq(3)
    expect(combined_nested_views.scan("hidden_field :_destroy").size).to eq(3)
    expect(combined_nested_views.scan("hidden_field :position").size).to eq(3)
    expect(edit_view.scan(/ax_text_field\(/).size).to eq(6)
    expect(nested_views.sum { |view| view.scan(/ax_text_field\(/).size }).to eq(8)
    expect(combined_nested_views.scan(/ax_select_field\(/).size).to eq(1)
    expect(footer_settings_views.join("\n").scan(/f\.(?:label|text_field|select|text_area)/).size).to eq(0)
    expect(edit_view.scan(/f\.(?:telephone_field|email_field)/).size).to eq(2)
    expect(edit_view).to include("ax_operational_panel(", "ax_form_actions(", 'class="ax-form-tabs__panels"', 'class="ax-form-tabs__panel')
    expect(edit_view).not_to include('class="tab-content"', 'class="tab-pane', 'class="ax-card__footer')
    expect(edit_view).to include("footer-contact-icon--whatsapp", "footer-contact-icon--email")
    expect(stylesheet).to include(".footer-nested-position", 'html[data-admin-theme="dark"] .footer-contact-icon--whatsapp')
  end

  it "usa metric cards e empty state compartilhados na auditoria de acessos" do
    expect(access_audit_logs_view).to include('class="ax-metric-grid')
    expect(access_audit_logs_view.scan("ax_metric_card").size).to eq(4)
    expect(access_audit_logs_view).to include("ax_empty_state")
    expect(access_audit_logs_view).not_to include("access-audit-kpi")
    expect(access_audit_logs_view).not_to match(/background:\s*#fff/i)
    expect(access_audit_logs_view).to include("var(--admin-ink)", "var(--ab-muted)", "var(--ax-border-soft)")
    expect(access_audit_logs_view).not_to match(/color:\s*#(?:0f172a|475569|64748b)/i)
  end

  it "trata pills estruturais como componentes dark, sem depender de badge" do
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-field-group__token/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-form-section__eyebrow/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-form-section__pill/)
  end


  it "mantem alerts light e dark em um componente isolado" do
    error_summary_view = File.read(File.expand_path("../../../app/views/admin/shared/ui/_error_summary.html.erb", __dir__))

    expect(alert_stylesheet).to match(/(?:^|\n)\.ax-alert\s*\{/)
    expect(alert_stylesheet).to match(/\.ax-alert:focus-visible/)
    expect(alert_stylesheet).to match(/\.ax-alert__content\s*\{[^}]*min-width:\s*0;/m)
    expect(alert_stylesheet).to match(/\.ax-alert__list li\s*\{[^}]*overflow-wrap:\s*anywhere;/m)
    expect(alert_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-alert--danger/)
    expect(alert_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-alert--warning/)
    expect(alert_stylesheet).to match(/@media \(max-width: 639px\)/)
    expect(error_summary_view).to include('aria-live="assertive"', 'aria-atomic="true"', 'tabindex="-1"', 'class="ax-alert__icon" aria-hidden="true"', 'class="ax-alert__content"')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-alert(?:--|__|\s*\{)/)
  end


  it "mantem switches e checks light e dark em um componente isolado" do
    expect(switch_stylesheet).to match(/(?:^|\n)\.ax-switch\s*\{/)
    expect(switch_stylesheet).to match(/\.ax-switch__input:checked \+ \.ax-switch__track/)
    expect(switch_stylesheet).to match(/\.ax-switch:hover \.ax-switch__track/)
    expect(switch_stylesheet).to match(/\.ax-switch__input:disabled \+ \.ax-switch__track/)
    expect(switch_stylesheet).to match(/\.ax-switch:has\(\.ax-switch__input:disabled\)/)
    expect(switch_stylesheet).to match(/@media\s*\(prefers-reduced-motion:\s*reduce\)/)
    expect(switch_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-switch__track/)
    expect(switch_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-check/)
    expect(switch_field_view).to include('role: "switch"', 'aria-hidden="true"')
    expect(switch_field_view).not_to match(/\bstyle\s*=/i)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-(?:switch|check)(?:__|--|\s*\{)/)
  end


  it "mantem upload light e dark em um componente isolado" do
    expect(upload_stylesheet).to match(/(?:^|\n)\.ax-upload-control\s*\{/)
    expect(upload_stylesheet).to match(/(?:^|\n)\.ax-file-field__control\s*\{/)
    expect(upload_stylesheet).to include(
      ".ax-file-upload__input:focus-visible + .ax-upload-button",
      ".ax-file-upload__input:disabled + .ax-upload-button",
      ".ax-file-field__input:disabled + .ax-file-field__button",
      "clip-path: inset(50%)"
    )
    expect(upload_stylesheet).to match(/@media \(max-width: 620px\)[\s\S]*\.ax-file-field__control/)
    expect(upload_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-upload-control/)
    expect(upload_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-file-field__control/)
    expect(file_upload_button_view.index("form.file_field")).to be < file_upload_button_view.index("form.label")
    expect(file_field_view).to include('role="status"', 'aria-live="polite"', 'aria-atomic="true"')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-(?:upload|file-upload)(?:__|--|\s*\{)/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-file-field(?:__|--|\s*\{)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.ax-file-field/)
  end

  it "renderiza progresso dinamico sem estilo inline e reutiliza o componente nos cards de metrica" do
    expect(progress_view).not_to match(/\bstyle\s*=/i)
    expect(progress_view).not_to include("html_safe")
    expect(progress_view).to include('<progress class="ax-progress__bar"', 'max="100"', 'value="<%= pct %>"', 'aria-label="<%= accessible_label %>"')
    expect(progress_view).to include('label.presence || "Progresso: #{formatted_pct}%"')
    expect(progress_view).to include("tag.attributes(data:)")
    expect(progress_view).to include('%i[green red amber blue]', 'ax-progress--#{normalized_tone}')
    expect(metric_card_view).not_to match(/\bstyle\s*=/i)
    expect(metric_card_view).to include("ax_progress(value: progress")
    expect(progress_stylesheet).to include(".ax-progress__bar::-webkit-progress-value", ".ax-progress__bar::-moz-progress-bar")
    expect(progress_stylesheet).to include(".ax-progress--green", ".ax-progress--amber", ".ax-progress--red", ".ax-progress--blue")
    expect(progress_stylesheet).to include(".ax-progress--lg", ".ax-progress__bar.is-running", "prefers-reduced-motion: reduce")
    expect(progress_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-progress/)
    expect(progress_stylesheet).to include("forced-colors: active", "forced-color-adjust: none")
    expect(upload_stylesheet).not_to match(/(?:^|\n)\.ax-progress(?:__|--|\s*\{)/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-progress(?:__|--|\s*\{)/)
  end

  it "mantem a lista de arquivos light e dark em um componente isolado" do
    expect(file_list_stylesheet).to match(/(?:^|\n)\.ax-file-list\s*\{/)
    expect(file_list_stylesheet).to match(/\.ax-file-list__title:focus-visible/)
    expect(file_list_stylesheet).to match(/@media \(max-width: 620px\)[\s\S]*\.ax-file-list__item/)
    expect(file_list_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-file-list__item/)
    expect(file_list_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-file-list__title/)
    expect(file_list_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-file-list__error/)
    expect(attachment_item_view).to include('rel: "noopener"', 'class: "ax-file-list__title"', 'class="ax-file-list__status"')
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-file-list(?:__|--|\s*\{)/)
  end


  it "mantem estados vazios light e dark em um componente isolado" do
    expect(empty_state_stylesheet).to match(/(?:^|\n)\.ax-empty-state\s*\{/)
    expect(empty_state_stylesheet).to match(/(?:^|\n)\.ax-empty-state--compact\s*\{[^}]*padding:\s*20px 12px;[^}]*border:\s*0;/m)
    expect(empty_state_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-empty-state\s*\{/)
    expect(empty_state_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-empty-state__icon/)
    expect(empty_state_stylesheet).to include("var(--ax-dark-info-surface)", "var(--ax-dark-info-text)", "var(--ax-dark-text-muted)")
    expect(empty_state_stylesheet).to match(/\.ax-empty-state__action\s*\{[^}]*flex-wrap:\s*wrap;/m)
    expect(empty_state_stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.ax-empty-state[^}]*!important/m)
    expect(empty_state_stylesheet).to match(/@media \(max-width: 639px\)[^{]*\{[^}]*\.ax-empty-state/m)
    expect(empty_state_view).to include('role="status"', 'aria-live="polite"', 'aria-atomic="true"', 'aria-hidden="true"', '"ax-empty-state--compact" if compact')
    expect(compact_empty_state_views).to all(include("compact: true"))
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-empty-state(?:__|--|\s*\{)/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.habitation-form-ui \.ax-empty-state/)
  end


  it "mantem cards de metrica light e dark em um componente isolado" do
    expect(metric_card_stylesheet).to match(/(?:^|\n)\.ax-metric-card\s*\{/)
    expect(metric_card_stylesheet).to match(/\.ax-metric-card__value\s*\{[^}]*overflow-wrap:\s*anywhere;/m)
    expect(metric_card_stylesheet).to include(".ax-metric-card > .ax-progress")
    expect(metric_card_stylesheet).to match(/@media\s*\(max-width:\s*639px\)[^{]*\{[^}]*\.ax-metric-grid/m)
    expect(metric_card_stylesheet).to match(/grid-template-columns:\s*repeat\(auto-fit, minmax\(140px, 1fr\)\)/)
    expect(metric_card_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-metric-card\s*\{/)
    expect(metric_card_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-metric-card__value/)
    expect(metric_card_view).to include('aria-label="<%= label %>"', "ax_progress(value: progress")
    expect(metric_card_stylesheet).not_to match(/\.ax-metric-card(?::hover|:focus|:focus-visible)/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-metric-(?:grid|card)(?:__|--|\s*\{)/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-dashboard \.ax-metric-card/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.habitation-form-ui \.ax-metric-card/)
  end


  it "mantem avisos inline light e dark em um componente isolado" do
    expect(inline_notice_stylesheet).to match(/(?:^|\n)\.ax-inline-notice\s*\{/)
    expect(inline_notice_stylesheet).to match(/\.ax-inline-notice\s*\{[^}]*border-left-width:\s*3px;/m)
    %w[neutral warning info success danger].each do |tone|
      expect(inline_notice_stylesheet).to match(/(?:^|\n)\.ax-inline-notice--#{tone}\s*\{/)
    end
    %w[warning info success danger].each do |tone|
      expect(inline_notice_stylesheet).to match(
        /data-admin-theme=["']dark["'][^{]*\.ax-inline-notice--#{tone}/
      )
    end
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-inline-notice(?:--|__|\s*\{)/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.seo-dashboard-page \.ax-inline-notice/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.habitation-form-ui \.ax-inline-notice/)
    expect(inline_notice_stylesheet).to match(/\.ax-inline-notice__content\s*\{[^}]*min-width:\s*0;/m)
    expect(inline_notice_stylesheet).to match(/\.ax-inline-notice__content--multiline\s*\{[^}]*white-space:\s*pre-line;/m)
    expect(inline_notice_stylesheet).to match(/\.ax-inline-notice--compact\s*\{[^}]*min-height:\s*28px;[^}]*padding:\s*5px 7px;/m)
    expect(inline_notice_stylesheet).to match(/@media \(max-width: 639px\)[^{]*\{[^}]*\.ax-inline-notice/m)
  end


  it "mantem o aviso inline compartilhado sem apresentacao embutida na view" do
    expect(inline_notice_view).not_to include("style=")
    expect(inline_notice_view).not_to include("notice_tones")
    expect(inline_notice_view).not_to include("notice_style")
    expect(inline_notice_view).to include('"ax-inline-notice--#{tone}"')
    expect(inline_notice_view).to include('"ax-inline-notice--compact" if compact', 'role="<%= notice_role %>"', 'aria-live="<%= aria_live %>"', 'aria-atomic="true"')
    expect(inline_notice_view).to include('<div class="ax-inline-notice__content"><%= body %></div>')
    expect(admin_ui_helper_source).to include('danger ? "alert" : "status"', 'danger ? "assertive" : "polite"')
    expect(inline_notice_consumer_views).to all(include("ax_inline_notice("))
    expect(inline_notice_consumer_views.join).not_to include('<div class="ax-inline-notice')
  end


  it "mantem itens de registro light e dark em um componente isolado" do
    expect(record_item_stylesheet).to match(/(?:^|\n)\.ax-record-item\s*\{/)
    expect(record_item_stylesheet).to match(/(?:^|\n)\.ax-record-item__main\s*\{[^}]*display:\s*flex/m)
    expect(record_item_stylesheet).to match(/(?:^|\n)\.ax-record-item:focus-within\s*\{/)
    expect(record_item_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-record-item\s*\{/)
    expect(record_item_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-record-item:focus-within/)
    expect(record_item_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-record-item__icon/)
    expect(record_item_stylesheet).not_to include(".ax-record-item:hover")
    expect(record_item_stylesheet).to match(/@media\s*\(max-width:\s*640px\)[^{]*\{.*\.ax-record-item__actions\s*\{[^}]*width:\s*100%/m)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-record-item(?:__|--|\s*\{)/)
    expect(stylesheet).to match(/(?:^|\n)\.habitation-form-ui \.ax-record-item/)
    expect(stylesheet).to match(/(?:^|\n)\.wa-inbox-conversation__card\.ax-record-item/)
  end


  it "mantem modais rapidos light e dark em um componente isolado" do
    expect(quick_modal_stylesheet).to match(/(?:^|\n)\.ax-quick-modal\s*\{/)
    expect(quick_modal_stylesheet).to match(/\.ax-quick-modal--sm \.ax-quick-modal__panel/)
    expect(quick_modal_stylesheet).to match(/\.ax-quick-modal--lg \.ax-quick-modal__panel/)
    expect(quick_modal_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-quick-modal__panel/)
    expect(quick_modal_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-quick-modal \.ax-icon-btn\s*\{[^}]*background:[^;]+!important/m)
    expect(quick_modal_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-quick-modal__error/)
    expect(quick_modal_stylesheet).to match(/\.ax-quick-modal__title-icon\s*\{[^}]*color:\s*var\(--admin-primary/m)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-quick-modal(?:__|--|\s*\{)/)
    expect(stylesheet).to match(/(?:^|\n)\.seo-strategy-modal \.ax-quick-modal__panel/)
    expect(stylesheet).to match(/(?:^|\n)\.automation-workflow-monitor-modal \.ax-quick-modal__panel/)
  end

  it "mantem a central do imovel legivel em todas as abas do modal dark" do
    expect(audit_history_modal_stylesheet).to match(/\.habitation-audit-modal\s*\{[^}]*--hab-audit-card-bg:\s*#fff;/m)
    expect(audit_history_modal_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.habitation-audit-modal/)
    expect(audit_history_modal_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.habitation-audit-modal\s*\{[^}]*--hab-audit-card-bg:\s*var\(--ax-dark-surface-raised/m)
    expect(audit_history_modal_stylesheet).to match(/\.habitation-audit-tab:focus-visible/)
    expect(audit_history_modal_stylesheet).to match(/\.habitation-operational-kpis article/)
    expect(audit_history_modal_stylesheet).to match(/\.habitation-publication-summary article/)
    expect(audit_history_modal_stylesheet).to match(/\.ax-tl-card/)
    expect(audit_history_modal_stylesheet).to match(/\.ax-tl-changes li/)
    expect(audit_history_modal_stylesheet).to match(/\.habitation-publication-channel\.is-active/)
    expect(audit_history_modal_stylesheet).to match(/\.habitation-publication-history\s*\{[^}]*margin-top:\s*20px;[^}]*padding-top:\s*20px;/m)
    expect(audit_history_modal_stylesheet).not_to include("background: #fff")
    expect(audit_history_modal_stylesheet).not_to include('html[data-admin-theme="dark"]')
    expect(audit_history_modal_view.scan(/background:\s*#fff(?:fff)?\b/i)).to be_empty
    expect(audit_history_modal_view.scan(/background:\s*var\(--hab-audit-card-bg,/).size).to eq(5)
  end


  it "impede superficies claras nos botoes de icone e toggles ativos do dark" do
    expect(icon_button_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*:where\(\.ax-ico-btn, \.ax-icon-btn\)\s*\{/)
    expect(toggle_chip_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-toggle-chip\.is-checked[^}]*background-color:[^;]*!important/m)
    expect(toggle_chip_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-toggle-chip:has\(\.ax-toggle-chip__input:checked\)[^}]*color:[^;]*!important/m)
  end

  it "inclui as folhas operacionais do admin no contrato dark global" do
    labels = admin_dark_contract_paths.map { |path| admin_stylesheet_label(path) }

    expect(labels).to include(
      "admin.css",
      "admin_tailwind.css",
      "admin/habitations_catalog.css",
      "admin/components/quick_modal.css"
    )
    expect(labels).not_to include("admin_compat.css", "admin/theme_tokens.css")
  end

  it "mantem tokens dark escopados em todas as folhas proprias do admin" do
    offenders = admin_dark_contract_paths.flat_map do |path|
      File.read(path).scan(/([^{}]+)\{([^{}]*)\}/m).filter_map do |selector, declarations|
        next unless declarations.include?("var(--ax-dark-")
        next if selector.include?("data-admin-theme")

        "#{admin_stylesheet_label(path)}: #{selector.strip.gsub(/\s+/, ' ')}"
      end
    end

    expect(offenders).to be_empty,
      "tokens --ax-dark-* fora do escopo data-admin-theme: #{offenders.join(', ')}"
  end

  it "nao permite superficies brancas opacas nas regras dark das folhas proprias do admin" do
    opaque_white_values = %w[#fff #ffffff white rgb(255,255,255) rgba(255,255,255,1)]
    offenders = admin_dark_contract_paths.flat_map do |path|
      File.read(path).scan(/([^{}]+)\{([^{}]*)\}/m).flat_map do |selector, declarations|
        next [] unless selector.include?("data-admin-theme")

        declarations.scan(/(?:^|;)\s*background(?:-color)?\s*:\s*([^;]+)/i).filter_map do |match|
          value = match.first.sub(/\s*!important\s*\z/i, "").strip.downcase.gsub(/\s+/, "")
          next unless opaque_white_values.include?(value)

          "#{admin_stylesheet_label(path)}: #{selector.strip.gsub(/\s+/, ' ')} => #{value}"
        end
      end
    end

    expect(offenders).to be_empty,
      "superficies brancas opacas no tema dark: #{offenders.join(', ')}"
  end

  it "preserva os fallbacks claros dos componentes que tambem atendem ao tema light" do
    expect(quick_modal_stylesheet).to match(/\.ax-quick-modal__panel\s*\{[^}]*background:\s*#fff;/m)
    expect(toggle_chip_stylesheet).to match(/\.ax-toggle-chip\s*\{[^}]*background:\s*#fff;/m)
  end


  it "mantem campos limpaveis light e dark em um componente isolado" do
    expect(clearable_control_stylesheet).to match(/(?:^|\n)\.ax-clearable-control\s*\{/)
    expect(clearable_control_stylesheet).to match(/\.ax-clearable-control__button:focus-visible/)
    expect(clearable_control_stylesheet).to include(
      "padding-right: 2rem !important",
      ".ax-clearable-control--select .ax-clearable-control__button",
      ".ax-clearable-control--number .ax-clearable-control__button",
      ".ax-clearable-control--date .ax-clearable-control__button",
      ".ax-clearable-control--multiline .ax-clearable-control__button"
    )
    expect(clearable_control_stylesheet).to match(/@media \(prefers-reduced-motion: reduce\)/)
    expect(clearable_control_stylesheet).to match(/\[data-admin-theme=["']dark["']\] \.ax-clearable-control__button/)
    expect(clear_field_controller).to include(
      "this.controlUnavailable(control, tomSelect)",
      "control.disabled",
      "control.readOnly",
      "tomSelect?.isDisabled",
      "tomSelect?.isLocked",
      "control.focus({ preventScroll: true })"
    )
    expect(clearable_field_views).to all(include('aria-hidden="true"'))
    expect(clearable_field_views[0]).to include("ax-clearable-control--multiline")
    expect(clearable_field_views[1]).to include("ax-clearable-control--select")
    expect(clearable_field_views[2]).to include("ax-clearable-control--number")
    expect(clearable_field_views[3]).to include("ax-clearable-control--date")
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-clearable-control(?:__|--|\s*\{)/)
    expect(stylesheet).to match(/\.habitations-inspector \.ax-clearable-control--select \.ts-wrapper/)
  end

  it "mantem formularios de filtro densos, semanticos e responsivos em um componente isolado" do
    expect(filter_form_view).to include('role="search"', 'aria-label="<%= filter_label %>"', 'aria-label="Ações dos filtros"')
    expect(filter_form_stylesheet).to match(/(?:^|\n)\.ax-filter-form\s*\{/)
    expect(filter_form_stylesheet).to match(/\.ax-filter-form:focus-within/)
    expect(filter_form_stylesheet).to include("minmax(min(170px, 100%), 1fr)", ".ax-filter-form__fields > *")
    expect(filter_form_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-filter-form\s*\{/)
    expect(filter_form_stylesheet).to match(/@media \(max-width: 767px\)[\s\S]*\.ax-filter-form\s*\{/)
    expect(filter_form_stylesheet).to match(/@media \(max-width: 420px\)[\s\S]*\.ax-filter-form__actions \.ax-btn/)
    expect(filter_form_stylesheet).to match(/@media \(prefers-reduced-motion: reduce\)/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-filter-form(?:__|\s*\{)/)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.ax-filter-form/)
    expect(stylesheet).to match(/\.ax-system \.ax-filter-form/)
  end


  it "mantem grupos de input light e dark em um componente isolado" do
    expect(input_group_stylesheet).to match(/(?:^|\n)\.ax-input-group\s*\{/)
    expect(input_group_stylesheet).to match(/\.ax-input-group--sm \.ax-input-group__addon/)
    expect(input_group_stylesheet).to match(/\.ax-input-group__addon:first-child/)
    expect(input_group_stylesheet).to match(/\.ax-input-group:focus-within \.ax-input-group__addon/)
    expect(input_group_stylesheet).to match(/\.ax-input-group:has\(:disabled\) \.ax-input-group__addon/)
    expect(input_group_stylesheet).to match(/prefers-reduced-motion:\s*reduce/)
    expect(input_group_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-input-group__addon/)
    expect(input_group_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-input-group > \.ax-btn\.ax-btn--ghost/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-input-group(?:__|--|\s*\{)/)
    expect(stylesheet).to match(/(?:^|\n)\.habitation-form-ui \.ax-input-group > \.ax-control/)
    expect(stylesheet).to match(/(?:^|\n)\.whatsapp-campaign-group-field \.ax-input-group/)
  end


  it "aplica no markup o tamanho declarado pelo helper de input agrupado" do
    input_group_partial = File.read(File.expand_path("../../../app/views/admin/shared/ui/_input_group.html.erb", __dir__))

    expect(input_group_partial).to include('"ax-input-group--#{normalized_size}"')
  end


  it "mantem grupos de campo e a cascata legada em um componente isolado" do
    expect(field_group_stylesheet.scan(/(?:^|\n)\.ax-field-group\s*\{/).size).to eq(1)
    expect(field_group_stylesheet).to include("var(--ax-border-soft)", "var(--ax-panel-soft)", "var(--ab-muted)")
    expect(field_group_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-field-group--panel/)
    expect(field_group_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-field-group__title/)
    expect(field_group_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-field-group__token/)
    expect(field_group_stylesheet).to include("overflow-wrap: anywhere", "max-width: min(100%, 220px)")
    expect(field_group_stylesheet).to match(/@media \(max-width: 620px\)[\s\S]*\.ax-field-group__header[^{]*\{[^}]*flex-wrap:\s*wrap;/m)
    field_group_view = File.read(File.expand_path("../../../app/views/admin/shared/ui/_field_group.html.erb", __dir__))
    expect(field_group_view).not_to match(/\bstyle\s*=/i)
    expect(field_group_view).to include("ax-field-group__header", "ax-field-group__title", "ax-field-group__token", "ax-field-group__actions", "ax-field-group__body")
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-field-group(?:__|--|\s*\{)/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.habitation-form-ui \.ax-field-group--panel/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.distribution-rule-workspace \.ax-field-group__title/)
  end


  it "mantem dropdowns ricos do Tom Select no contrato compartilhado de formulario" do
    expect(form_control_stylesheet).to match(/(?:^|\n)\.ax-select-dropdown\s*\{/)
    expect(form_control_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-select-dropdown\s*\{/)
    expect(form_control_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-select-option__description/)
    expect(form_control_stylesheet).to match(/\.ax-select-dropdown :where\(\.active, \.selected\)/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-select-dropdown(?:\s|\.)/)
  end


  it "mantem o controle nativo AX light e dark no componente de formulario" do
    expect(form_control_stylesheet).to match(/(?:^|\n)\.ax-control,/)
    expect(form_control_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*:where\([^{]*\.ax-control,/m)
    expect(form_control_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*:where\([^{]*\.ax-control,[^{]*\):hover/m)
    expect(form_control_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*:where\([^{]*\.ax-control:disabled/m)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-control,/)
    expect(stylesheet).not_to match(/(?:^|\n)\[data-admin-theme=["']dark["']\] \.ax-control\s*\{/)
  end

  it "mantem a acao acoplada do multiselect escura inclusive em hover e foco" do
    expect(form_control_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-multiselect__action\s*\{[^}]*background:\s*var\(--ax-dark-surface-raised/m)
    expect(form_control_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-multiselect__action:hover\s*\{[^}]*background:\s*var\(--ax-dark-surface-hover/m)
    expect(form_control_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-multiselect__action:focus-visible\s*\{[^}]*color:\s*var\(--ax-dark-text/m)
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.habitation-form-ui \.ax-multiselect__action/)
  end

  it "preserva o pull-to-refresh light e aplica a variante dark no componente global" do
    admin_stylesheet = File.read(File.expand_path("../../../app/assets/stylesheets/admin.css", __dir__))

    expect(admin_stylesheet).to match(/\.admin-ptr-pill\s*\{[^}]*background:\s*#fff/m)
    expect(admin_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.admin-ptr-pill\s*\{[^}]*background:\s*var\(--ax-dark-surface-raised/m)
    expect(admin_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.admin-ptr-pill\s*\{[^}]*color:\s*var\(--ax-dark-text/m)
  end


  it "aplica o tema dark aos campos AX mesmo sem a classe ax-control" do
    expect(form_control_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*:where\([^{]*\.ax-field input:not\(\[type="color"\]\)/m)
    expect(form_control_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*:where\(select\.ax-control, \.ax-field select\) option/)
    expect(form_control_stylesheet).to match(/\.ax-field input:disabled/)
    expect(form_control_stylesheet).to match(/\.ax-field textarea\[readonly\]/)
  end


  it "mantem popovers e detalhes de midia legiveis dentro do modal dark" do
    expect(media_modal_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-media-popover__body/)
    expect(media_modal_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-media-compact-details > summary:focus-visible/)
    expect(media_modal_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-media-source-notice__copy strong/)
    expect(media_modal_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-media-source-notice__copy span/)
  end


  it "usa os contratos compartilhados nos gatilhos e menus de imovel" do
    expect(property_catalog_actions_view.scan(/class="ax-btn ax-btn--icon admin-property-action-trigger"/).size).to eq(2)
    expect(property_catalog_actions_view.scan(/class="ax-menu ax-menu--end admin-property-menu/).size).to eq(2)
    expect(property_catalog_actions_view).not_to include('style="right: 0; left: auto;"')
    expect(property_catalog_actions_view).to include('class: "ax-menu__item ax-menu__item--danger')
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.admin-property-menu__status/)
  end

  it "remove estilos inline do formulario de distribuicao em favor dos contratos compartilhados" do
    combined_view = distribution_rule_form_views.join("\n")
    summary_view = File.read(File.expand_path("../../../app/views/admin/distribution_rules/_form_summary.html.erb", __dir__))
    agent_view = File.read(File.expand_path("../../../app/views/admin/distribution_rules/_agent_fields.html.erb", __dir__))

    expect(combined_view).not_to match(/\bstyle\s*=/i)
    expect(combined_view).to include("ax-field__error tw-hidden")
    expect(combined_view).to include("bi bi-whatsapp tw-text-green-600")
    expect(combined_view).to include("tw-mt-3 tw-mb-0")
    expect(summary_view).to include('role="status"', 'aria-live="polite"', 'aria-labelledby="distribution-rule-summary-title"')
    expect(agent_view).to include('aria-label="Remover <%= user_name %> da fila"', 'class="bi bi-trash" aria-hidden="true"')
    expect(stylesheet).not_to match(/\.distribution-rule-summary-card\s*\{[^}]*linear-gradient/m)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.distribution-rule-summary-card\s*\{[^}]*background:\s*var\(--admin-surface\)/m)
  end

  it "usa estado vazio compartilhado e acoes acessiveis na familia de distribuicao" do
    index_view = File.read(File.expand_path("../../../app/views/admin/distribution_rules/index.html.erb", __dir__))
    show_view = File.read(File.expand_path("../../../app/views/admin/distribution_rules/show.html.erb", __dir__))

    expect(index_view).to include("ax_empty_state(", 'aria: { label: "Ver regra #{rule.name}" }', 'aria: { label: "Excluir regra #{rule.name}" }')
    expect(index_view).not_to include('<div class="ax-empty">')
    expect(show_view).to include('class="distribution-rule-show__state"', 'class="drag-handle distribution-rule-show__queue-handle" title="Arrastar para reordenar" aria-hidden="true"')
  end

  it "usa larguras de tabela e estado vazio compartilhados na listagem de lojas" do
    expect(table_stylesheet).to include(".ax-table__col--xs", ".ax-table__col--compact", ".ax-table__col--sm", ".ax-table__col--md", ".ax-table__col--lg")
    expect(stores_index_view).not_to match(/\bstyle\s*=/i)
    expect(stores_index_view).to include("ax-table__col--xs", "ax-table__col--compact", "ax-table__col--sm", "ax-table__col--md", "ax-table__col--lg")
    expect(stores_index_view).to include("ax_empty_state(", "ax_badge(", "ax_icon_button(", '<caption class="tw-sr-only">', 'scope="col"', "compact: true")
    expect(stores_index_view).to include('if can?(:manage, :lojas)', 'label: "Ver loja #{store.name}"', 'label: "Editar loja #{store.name}"')
    expect(stores_index_view).not_to include('class="ax-badge', 'class: "ax-ico-btn"')
    expect(stores_index_view).not_to include('class="ax-empty"')
  end

  it "padroniza os cabecalhos da familia de lojas" do
    index_view, new_view, edit_view = store_workspace_views
    combined_view = store_workspace_views.join("\n")

    expect(combined_view).not_to match(/\bstyle\s*=/i)
    expect(combined_view.scan(/ax_workspace_heading\(/).size).to eq(3)
    expect(combined_view.scan(/Operação · Lojas/).size).to eq(3)
    expect(index_view).to include("store_heading_actions = capture", "method: :get", 'placeholder: "Buscar por nome..."')
    expect(new_view).to include('title: "Nova loja"', 'render "form", store: @store')
    expect(edit_view).to include('title: "Editar loja"', "turbo_confirm:", "can?(:manage, :lojas)")
  end

  it "compoe o detalhe da loja com workspace, metricas e paineis compartilhados" do
    expect(stores_show_view).not_to match(/\bstyle\s*=/i)
    expect(stores_show_view).to include("ax_workspace_heading(", 'class="ax-metric-grid', "ax_metric_card(")
    expect(stores_show_view).to include('if can?(:manage, :lojas)')
    expect(stores_show_view.scan(/ax_operational_panel\(/).size).to eq(4)
    expect(stores_show_view.scan(/ax_record_item\(/).size).to be >= 5
    expect(stores_show_view).to include("ax_empty_state(", 'class="store-location-map"')
    expect(stylesheet).to match(/\.store-location-map\s*\{[^}]*height:\s*350px;/m)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.store-location-map\s*\{[^}]*border-color:\s*var\(--ax-dark-border-soft\)/m)
  end

  it "compoe o formulario de loja com paineis, grupo de turno e mapa escopado" do
    form_view, shift_view = store_form_views
    combined_view = store_form_views.join("\n")

    expect(combined_view).not_to match(/\bstyle\s*=/i)
    expect(form_view.scan(/ax_operational_panel\(/).size).to eq(4)
    expect(form_view).to include("ax_form_actions(", "store-location-map--editor", "ax_input_group(", 'data: { store_map_picker_target: "radiusLabel" }')
    expect(form_view.scan(/ax_input_group\(/).size).to be >= 7
    expect(form_view.scan(/ax_text_field\(/).size).to eq(7)
    expect(form_view.scan(/ax_select_field\(/).size).to eq(2)
    expect(form_view.scan(/f\.(?:label|select)/).size).to eq(0)
    expect(form_view.scan(/f\.(?:text_field|number_field)/).size).to eq(7)
    expect(form_view).not_to include('class="ax-badge ax-badge--blue"', '<span><i class="bi bi-telephone', '<span><i class="bi bi-award')
    expect(shift_view).to include("ax_field_group(", 'data-controller="store-operational-shift"')
    expect(shift_view).not_to include('class="ax-card')
    expect(combined_view).to include("store-map-picker#updateRadius", "cep-lookup#geocodeFromNumber", "store-operational-shift#sync")
    expect(stylesheet).to match(/\.store-location-map--editor\s*\{\s*height:\s*400px;/)
  end

  it "compartilha listas de passos e a tabela operacional nas configuracoes de push" do
    expect(field_feedback_stylesheet).to match(/\.ax-field__hint--steps\s*\{[^}]*padding-left:\s*18px;[^}]*line-height:\s*1\.6;/m)
    expect(field_feedback_stylesheet).to match(/\.ax-field__hint--steps-spacious\s*\{[^}]*line-height:\s*1\.7;/m)
    expect(settings_step_views).to all(include("ax-field__hint--steps"))
    expect(settings_step_views.join("\n")).not_to include("padding-left:18px;margin:0;line-height:")

    expect(push_settings_view).not_to match(/\bstyle\s*=/i)
    expect(push_settings_view).to include("ax_workspace_heading(", 'class="ax-table-wrap"', 'class="ax-table"')
    expect(push_settings_view).to include("tw-text-red-600 tw-font-bold", "ax-num tw-text-ink-muted")
  end

  it "compoe as configuracoes de leads sem CSS embutido e preserva os paineis condicionais" do
    expect(lead_settings_view).not_to match(/<style|\bstyle\s*=/i)
    expect(lead_settings_view).to include("ax_workspace_heading(", "ax_error_summary(@lead_setting)")
    expect(lead_settings_view.scan(/ax_operational_panel\(/).size).to eq(6)
    expect(lead_settings_view.scan(/class=\"section-toggle-container/).size).to eq(2)
    expect(lead_settings_view.scan(/ax-field-group-stack/).size).to eq(2)
    expect(field_group_stylesheet).to match(/\.ax-field-group-stack\s*\{[^}]*border-left:\s*2px solid var\(--admin-primary/m)
    expect(lead_settings_view).to include(
      'data: { controller: "lead-settings" }',
      'data-lead-settings-target="stickinessSection"',
      'data-lead-settings-target="secureSection"',
      "change->lead-settings#toggleStickiness",
      "change->lead-settings#toggleSecure"
    )
  end


  it "padroniza os workspaces de SMTP, atendimento WhatsApp e notificacoes globais" do
    email_view, whatsapp_view, system_view = notification_settings_workspace_views
    combined_view = notification_settings_workspace_views.join("\n")

    expect(combined_view).not_to match(/\bstyle\s*=/i)
    expect(combined_view.scan(/ax_workspace_heading\(/).size).to eq(3)
    expect(email_view).to include("Configurações · Notificações", "email_status", "ax_error_summary(@email_setting)")
    expect(whatsapp_view).to include("Configurações · Atendimento", "admin_whatsapp_integration_path", "ax_toggle_chip(")
    expect(system_view).to include("Admin do Sistema", "ax-table__col--w-160", "update_tenant_fallbacks_admin_system_notification_settings_path")
    expect(system_view.scan(/ax-table__col--w-160/).size).to eq(2)
    expect(system_view).not_to include("ax-dashboard-command", "ax-property-form-command")
  end

  it "compoe as configuracoes de contato com campos e paineis compartilhados" do
    expect(contact_settings_view).not_to match(/\bstyle\s*=/i)
    expect(contact_settings_view).to include("ax_workspace_heading(", "ax_field_grid do", "ax_sticky_action_footer(")
    expect(contact_settings_view.scan(/ax_operational_panel\(/).size).to eq(2)
    expect(contact_settings_view.scan(/ax_input_group\(/).size).to eq(8)
    expect(contact_settings_view.scan(/class: "ax-control"/).size).to eq(8)
    expect(contact_settings_view.scan(/data: \{ controller: "phone-input" \}/).size).to eq(3)
    expect(contact_settings_view).not_to match(/\bbg-(?:primary|success|danger|info|light)\b/)
  end

  it "compoe oportunidades de marketing com registros, paineis e tabelas compartilhados" do
    expect(marketing_opportunities_view).not_to match(/\bstyle\s*=/i)
    expect(marketing_opportunities_view).to include("ax_workspace_heading(", "ax_record_item(", "ax_empty_state(")
    expect(marketing_opportunities_view.scan(/ax_operational_panel\(/).size).to eq(3)
    expect(marketing_opportunities_view.scan(/class=\"ax-table-wrap\"/).size).to eq(2)
    expect(marketing_opportunities_view).to include("ax-table__col--w-70", "ax-table__col--w-80", "ax-table__col--w-120", "ax-table__col--w-130")
    expect(table_stylesheet).to include(".ax-table__col--w-70", ".ax-table__col--w-80", ".ax-table__col--w-120", ".ax-table__col--w-130")
    expect(marketing_opportunities_view).not_to include('class="ax-card', 'class="ax-empty')
  end

  it "compoe o UTM Builder com campos, paineis e aviso compartilhados" do
    marketing_tools_view = File.read(File.expand_path("../../../app/views/admin/marketing_tools/index.html.erb", __dir__))

    expect(marketing_tools_view).not_to match(/\bstyle\s*=/i)
    expect(marketing_tools_view).to include("ax_workspace_heading(", "ax_field_grid do", "ax_form_actions(", "ax_inline_notice(")
    expect(marketing_tools_view.scan(/ax_operational_panel\(/).size).to eq(2)
    expect(marketing_tools_view.scan(/class: "ax-control"/).size).to eq(6)
    expect(marketing_tools_view).to include('id: "generated_utm_url"', "ax_standalone_field(", "readonly: true")
    expect(marketing_tools_view).not_to include('class="ax-card', 'class="ax-input"', "ax_page_header(")
  end

  it "compoe a listagem e o formulario de campanhas com contratos compartilhados" do
    index_view, form_view, new_view, edit_view = marketing_campaign_views
    combined_view = marketing_campaign_views.join("\n")

    expect(combined_view).not_to match(/\bstyle\s*=/i)
    expect(combined_view.scan(/ax_workspace_heading\(/).size).to eq(3)
    expect(combined_view.scan(/ax_operational_panel\(/).size).to eq(3)
    expect(index_view).to include('class="ax-table-wrap"', "ax_empty_state(", "ax_pagination @campaigns")
    expect(index_view).to include("MarketingCampaign::STATUSES", "turbo_confirm:", "ax-table__col--w-150")
    expect(form_view).to include("ax_field_grid do", "ax_form_actions(", "campaign.generated_url(request.base_url)")
    expect(form_view.scan(/ax_text_field\(/).size).to eq(9)
    expect(form_view.scan(/ax_select_field\(/).size).to eq(3)
    expect(form_view.scan(/ax_date_field\(/).size).to eq(2)
    expect(form_view.scan(/ax_currency_field\(/).size).to eq(1)
    expect(form_view.scan(/ax_standalone_field\(/).size).to eq(1)
    expect(form_view).not_to match(/f\.(?:label|text_field|number_field|date_field|select|collection_select|text_area)/)
    expect(form_view).not_to include("SeoSetting.order")
    expect(new_view).to include('render "admin/marketing_campaigns/form"')
    expect(edit_view).to include('subtitle: @campaign.name')
    expect(table_stylesheet).to include(".ax-table__col--w-150")
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.marketing-campaign-form \.tw-rounded-lg/)
  end

  it "compoe o editor SEO com campos, upload e contadores compartilhados" do
    expect(seo_setting_form_view).not_to match(/f\.(?:label|text_field|text_area|file_field)/)
    expect(seo_setting_form_view.scan(/ax_text_field\(/).size).to eq(11)
    expect(seo_setting_form_view.scan(/ax_file_field\(/).size).to eq(1)
    expect(seo_setting_form_view.scan(/label_meta:/).size).to eq(3)
    expect(seo_setting_form_view).to include("ax_toggle_chip(", "ax_sticky_action_footer(", 'data: { seo_field: "canonical" }')
    expect(seo_setting_form_view).to include('data: { seo_count: "title" }', 'data: { seo_count: "description" }', 'data: { seo_count: "intro" }')
  end

  it "mantem a linha de intervencao da automacao no contrato de controles compartilhados" do
    expect(automation_action_row_view).not_to match(/\bstyle\s*=/i)
    expect(automation_action_row_view).not_to include("ax-input", "ax-select")
    expect(automation_action_row_view.scan(/class=\"ax-control/).size).to eq(8)
    expect(automation_action_row_view).to include("automation-action-row__fields--wide", "automation-action-row__fields--wait")
    expect(stylesheet).to match(/\.automation-action-row__fields\s*\{[^}]*min-width:\s*200px;[^}]*flex:\s*1 1 200px;/m)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.automation-action-row\s*\{[^}]*background:\s*var\(--ax-dark-surface-raised\)/m)
  end

  it "compoe check-ins de campo com metricas, paineis e tabelas compartilhados" do
    expect(field_check_ins_index_view).not_to match(/\bstyle\s*=/i)
    expect(field_check_ins_index_view).to include("ax_workspace_heading(", 'class="ax-metric-grid', "ax_metric_card(")
    expect(field_check_ins_index_view.scan(/ax_operational_panel\(/).size).to eq(2)
    expect(field_check_ins_index_view.scan(/class=\"ax-table-wrap\"/).size).to eq(2)
    expect(field_check_ins_index_view.scan(/ax_empty_state\(/).size).to eq(2)
    expect(field_check_ins_index_view).to include("can?(:manage, :field_checkins)", "turbo_confirm:")
    expect(field_check_ins_index_view).to include("ax-table__col--w-140", "ax-table__col--w-170")
    expect(table_stylesheet).to include(".ax-table__col--w-140", ".ax-table__col--w-170")
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.field-checkins-admin \.ax-stat-/)
  end

  it "compoe o detalhe do check-in com cabecalho, paineis e registros compartilhados" do
    expect(field_check_ins_show_view).not_to match(/\bstyle\s*=/i)
    expect(field_check_ins_show_view).to include("ax_workspace_heading(", "ax_field_grid do", "ax_button(")
    expect(field_check_ins_show_view.scan(/ax_operational_panel\(/).size).to eq(2)
    expect(field_check_ins_show_view.scan(/ax_record_item\(/).size).to be >= 8
    expect(field_check_ins_show_view).to include("@check_in.checked_out_at", "@check_in.checkout_latitude")
  end

  it "compoe o catalogo de atributos com formularios, tabela e modais compartilhados" do
    expect(attribute_options_index_view).not_to match(/\bstyle\s*=/i)
    expect(attribute_options_index_view).to include("ax_workspace_heading(", "ax_filter_form(", "ax_field_grid do")
    expect(attribute_options_index_view.scan(/ax_operational_panel\(/).size).to eq(2)
    expect(attribute_options_index_view).to include("ax_select_field(", "ax_text_field(", "ax_quick_modal(")
    expect(attribute_options_index_view).to include('class="ax-table-wrap"', "ax_empty_state(", "ax_pagination @options")
    expect(attribute_options_index_view).to include("turbo_confirm:", "data-ax-modal-open=", "form.hidden_field :context", "form.hidden_field :category")
    expect(attribute_options_index_view).to include("ax-table__col--md", "ax-table__col--w-180", "ax-table__col--compact")
  end

  it "compoe a revisao manual de check-in com paineis, registros e tabelas compartilhados" do
    index_view, show_view = manual_checkin_request_views
    combined_view = manual_checkin_request_views.join("\n")

    expect(combined_view).not_to match(/\bstyle\s*=/i)
    expect(combined_view.scan(/ax_workspace_heading\(/).size).to eq(2)
    expect(combined_view.scan(/ax_operational_panel\(/).size).to eq(3)
    expect(index_view.scan(/class=\"ax-table-wrap\"/).size).to eq(2)
    expect(index_view.scan(/ax_empty_state\(/).size).to eq(2)
    expect(show_view.scan(/ax_record_item\(/).size).to be >= 5
    expect(index_view).to include("turbo_confirm:", "approve_admin_field_manual_checkin_request_path", "reject_admin_field_manual_checkin_request_path")
    expect(index_view).to include("ax-table__col--w-180", "ax-table__col--w-190")
    expect(table_stylesheet).to include(".ax-table__col--w-180", ".ax-table__col--w-190")
    expect(stylesheet).not_to match(/data-admin-theme=["']dark["'][^{]*\.manual-checkin-requests-admin/)
  end

  it "compoe a auditoria de exportacoes com metricas, filtros e tabela compartilhados" do
    expect(data_export_audit_logs_view).not_to match(/\bstyle\s*=/i)
    expect(data_export_audit_logs_view).to include("ax_workspace_heading(", 'class="ax-metric-grid', "ax_filter_form(")
    expect(data_export_audit_logs_view.scan(/ax_metric_card\(/).size).to eq(4)
    expect(data_export_audit_logs_view).to include("ax_field_grid do", "ax_operational_panel(", 'class="ax-table-wrap"')
    expect(data_export_audit_logs_view).to include("ax_empty_state(", "ax_pagination @logs")
    expect(data_export_audit_logs_view).to include("DataExportAuditLog::EXPORT_TYPES", "profile_filter_label(profile)")
    expect(data_export_audit_logs_view).to include("ax-table__col--w-100", "ax-table__col--w-120", "ax-table__col--w-130")
    expect(table_stylesheet).to include(".ax-table__col--w-100")
    expect(data_export_audit_logs_view).not_to include('class="ax-card', 'class="ax-empty', 'class: "ax-input"', 'class: "ax-select"')
  end

  it "compoe tarefas e seu modal compartilhado com contratos densos" do
    index_view, modal_view = task_views

    expect(task_views.join("\n")).not_to match(/\bstyle\s*=/i)
    expect(index_view).to include("ax_workspace_heading(", "ax_operational_panel(", 'class="ax-table-wrap"')
    expect(index_view).to include("ax_empty_state(", "ax_team_toggle(:comercial", "can?(:manage, :comercial)")
    expect(index_view).to include("complete_admin_task_path(task)", "turbo_confirm:")
    expect(index_view).to include("ax-table__col--w-40", "ax-table__col--w-120", "ax-table__col--w-170", "ax-table__text--truncate")
    expect(modal_view.scan(/class: "ax-control"/).size).to eq(4)
    expect(modal_view).to include('class="ax-control"', "ax_field_grid do", 'data-controller="ax-modal"')
    expect(modal_view).not_to include('class: "ax-input"', 'class: "ax-select"', 'class: "ax-textarea"')
    expect(table_stylesheet).to include(".ax-table__col--w-40", ".ax-table__text--truncate")
  end

  it "mantem a integracao do WhatsApp em componentes e feedbacks sem cores inline" do
    expect(whatsapp_integration_view).not_to match(/\bstyle\s*=/i)
    expect(whatsapp_integration_view).to include("ax_workspace_heading(", "ax_operational_panel(", "ax_inline_notice(")
    expect(whatsapp_integration_view).to include('data-controller="whatsapp-integration"', "wa-field--divider")
    expect(whatsapp_integration_view).to include('data-whatsapp-integration-target="signupFeedback"', 'data-whatsapp-integration-target="testResult"')
    expect(whatsapp_integration_view).to include("tw-text-green-600", "tw-text-amber-600")
    expect(whatsapp_integration_view).to include("ax-input-group__icon--whatsapp")
    expect(whatsapp_integration_view.scan(/ax_text_field\(/).size).to eq(16)
    expect(whatsapp_integration_view.scan(/ax_select_field\(/).size).to eq(4)
    expect(whatsapp_integration_view.scan(/f\.(?:label|text_field|password_field|url_field|select)/).size).to eq(0)
    expect(whatsapp_integration_view.scan(/f\.telephone_field/).size).to eq(1)
    expect(whatsapp_integration_view).not_to include("ContactSetting.first")
    expect(input_group_stylesheet).to match(/\.ax-input-group__icon--whatsapp\s*\{[^}]*color:\s*#16a34a;/m)
    expect(input_group_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-input-group__icon--whatsapp\s*\{[^}]*color:\s*#4ade80;/m)
    expect(whatsapp_integration_controller).to include("element.classList.remove(", 'element.classList.add(`ax-inline-notice--${tone}`)', "element.hidden = false")
    expect(whatsapp_integration_controller).not_to include("element.style.display", "element.style.borderColor", "element.style.background", "element.style.color", "tones()")
  end


  it "mantem as acoes dos templates WhatsApp no contrato de botoes" do
    expect(whatsapp_templates_index_view).not_to match(/\bstyle\s*=/i)
    expect(whatsapp_templates_index_view).to include('class: "ax-btn ax-btn--sm ax-btn--primary"', "Criar campanha")
    expect(button_stylesheet).to match(/a\.ax-btn\.ax-btn--primary:visited[\s\S]*color:\s*var\(--admin-primary-fg\)/)
  end


  it "centraliza ajuda do login e divisor da timeline sem estilos inline" do
    expect(admin_two_factor_challenge_view).not_to match(/\bstyle\s*=/i)
    expect(admin_two_factor_challenge_view).to include('class="login-hint"', 'autocomplete="one-time-code"', "códigos de backup")
    expect(admin_login_layout).to match(/\.login-hint\s*\{[^}]*color:\s*var\(--login-muted\);[^}]*font-size:\s*12px;/m)

    expect(lead_show_view).not_to match(/\bstyle\s*=/i)
    expect(lead_show_view).to include('class="ax-disclosure-divider tw-mt-2"', 'data-controller="ax-disclosure"')
    expect(disclosure_card_stylesheet).to match(/\.ax-disclosure-divider\s*\{[^}]*border-top:\s*1px dashed var\(--ax-border-soft\);/m)
    expect(disclosure_card_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-disclosure-divider\s*\{[^}]*var\(--ax-dark-border-soft\)/m)
  end

  it "compoe a configuracao de duas etapas sem estilos inline" do
    expect(two_factor_settings_view).not_to match(/\bstyle\s*=/i)
    expect(two_factor_settings_view).to include("ax_workspace_heading(", "ax_operational_panel(", "ax_field_group(", "ax_inline_notice(")
    expect(two_factor_settings_view).to include("current_admin_user.two_factor_required?", "turbo_confirm:")
    expect(two_factor_settings_view).to include("ax-btn ax-btn--danger", "two-factor-setup", "two-factor-qr", "two-factor-secret", "ax_standalone_field(")
    expect(two_factor_settings_view.scan("ax_standalone_field(").size).to eq(3)
    expect(stylesheet).to include(".two-factor-setup", ".two-factor-qr", ".two-factor-manual")
    expect(stylesheet).to match(/\.two-factor-qr\s*\{[^}]*width:\s*180px;[^}]*height:\s*180px;[^}]*background:\s*#fff;/m)
  end

  it "protege os codigos de backup com clipboard compartilhado e contrato dark" do
    expect(two_factor_backup_codes_view).not_to match(/\bstyle\s*=|\bonclick\s*=/i)
    expect(two_factor_backup_codes_view).to include("ax_workspace_heading(", "ax_operational_panel(", "ax_inline_notice(")
    expect(two_factor_backup_codes_view).to include('data-controller="clipboard"', 'data-action="clipboard#copy"', 'data-clipboard-target="source"', 'data-clipboard-target="content"')
    expect(two_factor_backup_codes_view).to include("@backup_codes.each", '@backup_codes.join("\\n")', "admin_two_factor_settings_path")
    expect(stylesheet).to include(".two-factor-backup-grid", ".two-factor-backup-code", ".two-factor-backup-actions")
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.layout-settings-workspace code\.two-factor-backup-code/)
  end

  it "compoe e ordena as secoes da home com a tabela compartilhada" do
    expect(home_sections_index_view).not_to match(/\bstyle\s*=/i)
    expect(home_sections_index_view).not_to include("form: { style:")
    expect(home_sections_index_view).to include("ax_workspace_heading(", "ax_operational_panel(", 'class="ax-table-wrap"', "ax_empty_state(")
    expect(home_sections_index_view).to include('data-controller="home-sections-sort"', "update_order_admin_home_sections_path")
    expect(home_sections_index_view).to include("toggle_active_admin_home_section_path(section)", "turbo_confirm:")
    expect(home_sections_index_view).to include("ax-table__col--w-80", "ax-table__col--w-120", "ax-table__col--w-220", "ax-table__row--sortable")
    expect(table_stylesheet).to include(".ax-table__row--sortable", ".ax-table__row--sortable:active")
  end

  it "compoe a listagem de proprietarios com filtros e tabela compartilhados" do
    expect(proprietors_index_view).not_to match(/\bstyle\s*=/i)
    expect(proprietors_index_view).to include("ax_workspace_heading(", "ax_filter_form(", "ax_field_grid do", "ax_operational_panel(")
    expect(proprietors_index_view.scan(/class: "ax-control"/).size).to eq(3)
    expect(proprietors_index_view).to include('class: "ax-search ax-search--fluid"')
    expect(proprietors_index_view).to include('class="ax-table-wrap"', "ax_empty_state(", "ax_pagination @proprietors")
    expect(proprietors_index_view).to include("@filters.values.any?(&:present?)", "@habitations_count_by_proprietor")
    expect(proprietors_index_view).to include("ax-table__col--w-150", "ax-table__col--w-160", "ax-table__col--compact", "ax-table__col--xs")
    expect(proprietors_index_view).to include(
      'for="filters_name"',
      'for="filters_city"',
      'for="filters_vista_code"',
      'for="filters_cpf_cnpj"',
      'label: "Editar proprietário #{proprietor.name}"'
    )
    expect(proprietors_index_view.scan(/ax_icon_button\(/).size).to eq(1)
    expect(table_stylesheet).to include(".ax-table__col--w-160")
    expect(proprietors_index_view).not_to include('class="ax-card', 'class="ax-empty', 'class: "ax-input"')
  end

  it "compoe os estados de atendimento expirado com o vazio compartilhado" do
    expect(lead_attend_expired_view).not_to match(/\bstyle\s*=/i)
    expect(lead_attend_expired_view).to include("ax_empty_state(", 'title: taken ? "Lead já atendido" : "Tempo esgotado"')
    expect(lead_attend_expired_view).to include('icon: taken ? "person-check" : "hourglass-bottom"')
    expect(lead_attend_expired_view).to include('ax_button("Ver meus leads", admin_leads_path')
    expect(lead_attend_expired_view).not_to include('class="ax-empty-state"', 'class="ax-page-title"')
  end

  it "mantem as secoes globais da sidebar tokenizadas e sem estilos inline" do
    section_keys = %w[product operation management growth public-site integrations settings account]

    expect(admin_sidebar_view).not_to match(/\bstyle\s*=/i)
    expect(admin_sidebar_view).not_to include("nav_section_style")

    section_keys.each do |key|
      expect(admin_sidebar_view).to include(%(data-nav-section="#{key}"))
      expect(admin_sidebar_view).to include(%(aria-controls="nav-section-#{key}"))
      expect(stylesheet).to include(%(.ax-nav__section[data-nav-section="#{key}"]))
      expect(stylesheet).to include("--nav-section-background: var(--admin-nav-#{key}-background)")
      expect(stylesheet).to include("--nav-section-shadow: var(--admin-nav-#{key}-shadow)")
    end

    expect(admin_sidebar_view).to include('data-controller="menu-sections"', 'data-action="menu-sections#toggle"')
    expect(admin_sidebar_view).to include("can_access.call", "tenant_owner?", "current_admin_user")
    expect(stylesheet).to include('html[data-admin-theme="dark"] .ax-nav__section[data-nav-section]')
    expect(stylesheet).to include(".ax-app.is-compact .ax-nav--sectioned > .ax-nav__section[data-nav-section]")
  end

  it "compoe o formulario de webhook com grupos e instrucoes compartilhados" do
    expect(webhook_settings_form_view).not_to match(/\bstyle\s*=/i)
    expect(webhook_settings_form_view.scan(/ax_input_group\(/).size).to eq(2)
    expect(webhook_settings_form_view).to include("ax_operational_panel(", "ax_field_grid do", "ax_switch_field(")
    expect(webhook_settings_form_view).to include("tw-text-green-600", "ax-field__hint--steps")
    expect(webhook_settings_form_view).to include("local_assigns[:main_only]", "webhook-editor-actions", "ax_code_snippet(")
    expect(webhook_settings_form_view).not_to include("webhook-editor-payload")
    expect(webhook_settings_form_view).not_to include("rgba(22,163,74,.1)", 'class="fab fa-whatsapp"')
  end

  it "compoe os webhooks de saida com controle e tabela compartilhados" do
    expect(webhook_outbound_settings_view).not_to match(/\bstyle\s*=/i)
    expect(webhook_outbound_settings_view).not_to include('class: "ax-input"')
    expect(webhook_outbound_settings_view).to include('class: "ax-control"')
    expect(webhook_outbound_settings_view).to include("ax_operational_panel(", 'class="ax-table-wrap"')
    expect(webhook_outbound_settings_view).to include("ax-table__col--w-120", "ax-table__col--sm", "ax-table__col--md")
    expect(webhook_outbound_settings_view).to include("test_admin_webhook_setting_path", "edit_admin_webhook_setting_path", "admin_webhook_setting_path")
    expect(webhook_outbound_settings_view).to include("share_tracking_admin_webhook_settings_path", "HabitationShareLink::MIN_EXPIRATION_DAYS", "HabitationShareLink::MAX_EXPIRATION_DAYS")
  end

  it "compoe alertas de marketing com registros, paineis e tabela compartilhados" do
    expect(marketing_alerts_index_view).not_to match(/\bstyle\s*=/i)
    expect(marketing_alerts_index_view).to include("ax_workspace_heading(", "ax_record_item(", "ax_empty_state(")
    expect(marketing_alerts_index_view.scan(/ax_operational_panel\(/).size).to eq(2)
    expect(marketing_alerts_index_view).to include('class="ax-table-wrap"', "admin_seo_dashboard_path")
    expect(marketing_alerts_index_view).to include("bs_to_ax[alert.level.to_s]", "status_ok =")
    expect(marketing_alerts_index_view).to include("ax-table__col--compact", "ax-table__col--w-80", "ax-table__col--w-100")
    expect(marketing_alerts_index_view).not_to include('class="ax-card', 'class="ax-empty')
  end

  it "compoe os imoveis priorizados para marketing com painel e tabela compartilhados" do
    expect(marketing_properties_index_view).not_to match(/\bstyle\s*=/i)
    expect(marketing_properties_index_view).to include("ax_workspace_heading(", "ax_operational_panel(", "ax_empty_state(")
    expect(marketing_properties_index_view).to include('class="ax-table-wrap"', "@property_insights.each")
    expect(marketing_properties_index_view).to include("habitation_path(habitation)", "admin_habitation_internal_path(habitation)")
    expect(marketing_properties_index_view).to include("ax-table__col--w-80", "ax-table__col--w-100", "ax-table__col--w-140", "ax-table__col--w-180")
    expect(marketing_properties_index_view).not_to include('class="ax-empty')
  end

  it "compoe o status da migracao de imagens com metricas e avisos compartilhados" do
    expect(image_migration_status_view).not_to match(/\bstyle\s*=/i)
    expect(image_migration_status_view).to include("ax_workspace_heading(", 'class="ax-metric-grid', "ax_metric_card(", "ax_inline_notice(")
    expect(image_migration_status_view.scan(/ax_metric_card\(/).size).to eq(4)
    expect(image_migration_status_view.scan(/ax_inline_notice\(/).size).to eq(3)
    expect(image_migration_status_view).to include("ax_progress(", 'class_name: "ax-progress--lg tw-mb-3"', 'image_migration_status_target: "executionProgressBar"')
    expect(image_migration_status_controller).to include("target.value = progress", 'classList.toggle("is-running"', 'setAttribute("aria-busy"')
    expect(image_migration_status_controller).not_to include("target.style.width", "progress-bar-animated", "progress-bar-striped")

    expect(storage_integration_view).not_to match(/\bstyle\s*=/i)
    expect(storage_integration_view).to include("ax_progress(", 'storage_public_photo_publish_target: "bar"')
    expect(storage_public_photo_publish_controller).to include("this.barTarget.value = percent", 'classList.toggle("is-running"', 'setAttribute("aria-busy"')
    expect(storage_public_photo_publish_controller).not_to include("barTarget.style.width", "parentElement?.setAttribute")
    expect(image_migration_status_view).to include("admin_sync_image_migration_path", "admin_retry_failed_image_migration_path", "turbo_confirm:")
    expect(image_migration_status_view).not_to include("Vista como fallback")
  end

  it "compoe eventos da automacao com metricas, filtros e tabela compartilhados" do
    expect(automation_events_index_view).not_to match(/\bstyle\s*=/i)
    expect(automation_events_index_view).to include("ax_workspace_heading(", 'class="ax-metric-grid', "ax_filter_form(", "ax_operational_panel(")
    expect(automation_events_index_view.scan(/ax_metric_card\(/).size).to eq(4)
    expect(automation_events_index_view.scan(/class: "ax-control"/).size).to eq(5)
    expect(automation_events_index_view).to include("ax_field_grid do", 'class="ax-table-wrap"', "ax_empty_state(", "ax_pagination(@events)")
    expect(automation_events_index_view).to include("reprocess_admin_automation_event_path(event)", "ignore_admin_automation_event_path(event)", "turbo_confirm:")
    expect(automation_events_index_view).to include("ax-table__col--w-120", "ax-table__col--w-130", "ax-table__col--w-150", "ax-table__col--w-180")
    expect(automation_events_index_view).not_to include('class="ax-card', 'class: "ax-input"')
  end

  it "compoe regras da automacao com paineis, registros, estados e historico compartilhados" do
    expect(automation_rules_index_view).not_to match(/\bstyle\s*=/i)
    expect(automation_rules_index_view).to include("ax_workspace_heading(", "ax_empty_state(", 'class="ax-table-wrap"')
    expect(automation_rules_index_view.scan(/ax_operational_panel\(/).size).to eq(3)
    expect(automation_rules_index_view.scan(/ax_record_item\(/).size).to eq(2)
    expect(automation_rules_index_view).to include("ax_badge(", "ax_button(", "safe_join([")
    expect(automation_rules_index_view).to include("toggle_active_admin_automation_rule_path(rule)", "edit_admin_automation_rule_path(rule)", "admin_automation_rule_path(rule)")
    expect(automation_rules_index_view).to include("turbo_confirm:", "create_example_admin_automation_rules_path", "builder_admin_automation_workflow_path(workflow)")
    expect(automation_rules_index_view).to include("ax-table__col--w-120", "ax-table__col--w-150", "admin_lead_path(run.lead)")
    expect(automation_rules_index_view).not_to include('class="ax-card', 'class="ax-empty')
  end

  it "compoe cadastro e edicao das regras com formulario compartilhado" do
    new_view, edit_view, form_view = automation_rule_form_views
    combined_view = automation_rule_form_views.join("\n")

    expect(combined_view).not_to match(/\bstyle\s*=/i)
    expect(combined_view).not_to include('class="ax-card', 'class: "ax-input"', 'class: "ax-select"', 'class="ax-badge')
    expect(new_view).to include("ax_workspace_heading(", 'render "form", rule: @rule')
    expect(edit_view).to include("ax_workspace_heading(", 'render "form", rule: @rule')
    expect(form_view.scan(/ax_operational_panel\(/).size).to eq(3)
    expect(form_view).to include("ax_error_summary(rule)", "ax_field_grid do", "ax_field_group(", "ax_toggle_chip(", "ax_badge(")
    expect(form_view).to include('controller: "automation-builder"', 'automation_builder_target: "trigger"', 'data-automation-builder-target="idleCond"')
    expect(form_view).to include('data-automation-builder-target="rows"', 'data-automation-builder-target="template"', 'automation_builder_target: "json"')
    expect(form_view).to include("simulate_admin_automation_rule_path(rule)", "simulate_admin_automation_rules_path", 'f.submit "Salvar regra"')
  end

  it "compoe a familia de metas de captacao com listagem e formulario compartilhados" do
    index_view, form_view, new_view, edit_view = captacao_goal_views
    combined_view = captacao_goal_views.join("\n")

    expect(combined_view).not_to match(/\bstyle\s*=/i)
    expect(combined_view.scan(/ax_workspace_heading\(/).size).to eq(3)
    expect(combined_view.scan(/ax_operational_panel\(/).size).to eq(3)
    expect(index_view).to include('class="ax-table-wrap"', "ax_badge(", "ax_empty_state(", "turbo_confirm:")
    expect(index_view).to include("ax-table__col--md", "ax-table__col--compact", "ax-table__col--lg")
    expect(form_view).to include("ax_field_grid do", "ax_date_field(", "ax_select_field(", "ax_number_field(", "ax_text_field(", "ax_form_actions(")
    expect(form_view).to include(":start_date", ":end_date", ":kind", ":target", ":foco_regiao", ":foco_valor_min", ":foco_valor_max")
    expect(new_view).to include('render "form", goal: @goal')
    expect(edit_view).to include("@goal.period_label", '@goal.kind.humanize')
    expect(combined_view).not_to include('class="ax-card', 'class="ax-empty')
  end

  it "compoe configuracoes de campo com paineis, switch, tabela e checklist compartilhados" do
    expect(field_settings_edit_view).not_to match(/\bstyle\s*=/i)
    expect(field_settings_edit_view).to include("ax_workspace_heading(", "ax_switch_field(", "ax_form_actions(", 'class="ax-metric-grid"', "ax_metric_card(")
    expect(field_settings_edit_view.scan(/ax_operational_panel\(/).size).to eq(3)
    expect(field_settings_edit_view).to include("ax_inline_notice(", 'class="ax-table-wrap"', "ax_empty_state(")
    expect(field_settings_edit_view).to include("ax-table__col--w-120", "ax-table__col--w-170", "ax-field__hint--steps")
    expect(field_settings_edit_view).to include("block_agent_admin_field_settings_path", "unblock_agent_admin_field_settings_path", "turbo_confirm:")
    expect(field_settings_edit_view).to include("new_admin_store_path", "admin_stores_path", "admin_field_settings_path")
    expect(field_settings_edit_view).to include('<caption class="tw-sr-only">', 'scope="col"', 'aria: { label: "Bloquear check-in para')
    expect(field_settings_edit_view).not_to include('class="ax-card', 'class="ax-empty', 'class="ax-table-shell"')
  end

  it "compoe redirects de SEO com cadastro, edicao inline e tabela compartilhados" do
    expect(seo_redirects_index_view).not_to match(/\bstyle\s*=/i)
    expect(seo_redirects_index_view).to include("ax_workspace_heading(", "ax_field_grid do", "ax_error_summary(")
    expect(seo_redirects_index_view.scan(/ax_operational_panel\(/).size).to eq(2)
    expect(seo_redirects_index_view).to include("ax_text_field(", "ax_select_field(", "ax_toggle_chip(")
    expect(seo_redirects_index_view).to include('class="ax-table-wrap"', "ax_empty_state(", "ax_pagination @seo_redirects")
    expect(seo_redirects_index_view).to include("ax-table__col--compact", "ax-table__col--w-120", "ax-table__col--w-140")
    expect(seo_redirects_index_view).to include("admin_seo_settings_path", "admin_seo_redirect_path(redirect)", "turbo_confirm:")
    expect(seo_redirects_index_view).to include(":from_path", ":to_path", ":status_code", ":active")
    expect(seo_redirects_index_view).not_to include('class="ax-card', 'class="ax-empty', 'class: "ax-input"', 'class: "ax-select"')
  end

  it "compoe auditoria de campo com metricas, filtros, registros e detalhe compartilhados" do
    index_view, show_view = field_audit_log_views
    combined_view = field_audit_log_views.join("\n")

    expect(combined_view).not_to match(/\bstyle\s*=/i)
    expect(combined_view.scan(/ax_workspace_heading\(/).size).to eq(2)
    expect(combined_view.scan(/ax_operational_panel\(/).size).to eq(2)
    expect(index_view).to include('class="ax-metric-grid', "ax_filter_form(", "ax_field_grid do", "ax_empty_state(", "ax_pagination @logs")
    expect(index_view.scan(/ax_metric_card\(/).size).to eq(4)
    expect(index_view).to include("ax_record_item(", "ax_badge(", "profile_filter_label(profile)")
    expect(index_view).to include(":action_filter", ":admin_user_id", ":profile_id", ":actor_admin_user_id", ":store_id", ":ip", ":start_date", ":end_date")
    expect(show_view).to include("ax_field_grid do", "ax_record_item(", "admin_field_check_in_path(@log.check_in_id)")
    expect(show_view.scan(/ax_record_item\(/).size).to be >= 7
    expect(combined_view).not_to include('class="ax-card', 'class="ax-empty', 'class: "ax-input"', 'class: "ax-select"')
  end

  it "compoe perfis de acesso com hierarquia, badges, painel e tabela compartilhados" do
    expect(profiles_index_view).not_to match(/\bstyle\s*=/i)
    expect(profiles_index_view).to include("ax_workspace_heading(", "ax_inline_notice(", "ax_operational_panel(")
    expect(profiles_index_view).to include('class="ax-table-wrap"', "ax_badge(", "ax_empty_state(")
    expect(profiles_index_view).to include("@vertical_profiles.size", "@horizontal_profiles.size", "@superior_profile[profile.id]")
    expect(profiles_index_view).to include("ax-table__col--w-180", "ax-table__col--w-130", "ax-table__col--md", "ax-table__col--sm", "ax-table__col--compact")
    expect(profiles_index_view).to include("edit_admin_profile_path(profile)", "admin_profile_path(profile)", "turbo_confirm:", "profile.locked?")
    expect(profiles_index_view).not_to include('class="ax-dashboard-command', 'class="ax-empty', 'class="ax-badge')
  end


  it "compoe o detalhe do perfil com cabecalho e geometria de tabela compartilhados" do
    expect(profiles_show_view).not_to match(/\bstyle\s*=/i)
    expect(profiles_show_view).to include("ax_workspace_heading(", "ax-table__col--w-220", "tw-mt-2")
    expect(profiles_show_view).to include("admin_profiles_path", "edit_admin_profile_path(@profile)")
    expect(profiles_show_view).not_to include("ax-dashboard-command", "ax-property-form-command")
  end


  it "padroniza os cabecalhos de conta e cartoes de apresentacao" do
    combined_view = ([account_settings_view] + presentation_card_workspace_views).join("\n")

    expect(combined_view).not_to match(/\bstyle\s*=/i)
    expect(account_settings_view).to include("ax_workspace_heading(", "Conta · Governança", "building-gear")
    expect(presentation_card_workspace_views).to all(include("ax_workspace_heading(", "WhatsApp · Atendimento", "person-badge"))
    expect(presentation_card_workspace_views.join.scan(/ax_workspace_heading\(/).size).to eq(3)
    expect(presentation_card_workspace_views.first).to include('actions: ax_button("Novo cartão"')
    expect(presentation_card_workspace_views.drop(1)).to all(include('actions: link_to("Voltar"'))
    expect(presentation_card_workspace_views.first.scan(/<caption class="tw-sr-only">/).size).to eq(2)
    expect(presentation_card_workspace_views.first.scan(/scope="col"/).size).to eq(9)
    expect(presentation_card_workspace_views.first.scan(/scope="row"/).size).to eq(2)
    expect(presentation_card_workspace_views.first).to include("ax_icon_button(", 'aria: { label: "Excluir cartão #{card.label}" }')
  end


  it "compartilha avatar entre preview e gerenciador de cartoes" do
    profile_preview, quick_edit_modal = presentation_card_support_views
    combined_view = presentation_card_support_views.join("\n")
    presentation_card_stylesheet = File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/presentation_cards.css", __dir__))

    expect(combined_view).not_to match(/\bstyle\s*=/i)
    expect(combined_view.scan(/ax_avatar\(/).size).to eq(2)
    expect(profile_preview).to include("size: :lg", "ax_inline_notice(")
    expect(quick_edit_modal).to include("size: :md", "tw-text-ink-muted", 'data-controller="ax-modal"')
    expect(quick_edit_modal).to include('data-controller="ax-disclosure"', "ax_switch_field(", "admin_presentation_card_path(card)")
    expect(quick_edit_modal.scan(/ax_standalone_field\(/).size).to eq(4)
    expect(quick_edit_modal).to include('id: "pc_use_photo_#{card.id}"', 'id: "pc_active_#{card.id}"', 'id: "pc_use_photo_new"')
    expect(quick_edit_modal).not_to include("text_field_tag", "text_area_tag", 'class="ax-input"', 'class="ax-textarea"')
    expect(quick_edit_modal).to include('aria-labelledby="presentationCardsManagerTitle"', "turbo_confirm:", "Excluir cartão <%= card.label %>")
    expect(presentation_card_stylesheet).to include(".pc-manager", ".pc-item__new-trigger:focus-visible", '[data-admin-theme="dark"] .pc-item', "@media (max-width: 639px)", "@media (prefers-reduced-motion: reduce)")
    expect(stylesheet).not_to match(/(?:^|\n)\.pc-(?:manager|item)/)
  end

  it "compoe o formulario de cartoes com campos e erros compartilhados" do
    expect(presentation_card_form_view).to include("ax_error_summary(card)", "ax_field_grid(", "ax_form_actions(")
    expect(presentation_card_form_view.scan(/ax_text_field\(/).size).to eq(2)
    expect(presentation_card_form_view).to include("type: :textarea", "ax_switch_field(")
    expect(presentation_card_form_view).not_to include("f.text_area", 'class: "ax-textarea"')
  end

  it "compoe o formulario de perfis sem CSS inline e com matriz dark" do
    expect(profiles_form_view).not_to match(/\bstyle\s*=/i)
    expect(profiles_form_view).not_to include("<style", "profiles-form-styles")
    expect(profiles_form_view).to include("prof-matrix__resource-col", "prof-matrix__action-col", "prof-matrix__scope-col")
    expect(profiles_form_view).to include('data: { controller: "profile-axis-context" }', 'data-profile-axis-context-target="verticalProfileField"', 'data-profile-axis-context-target="insertAfterField"')
    expect(profiles_form_view).to include('profile[permissions][#{resource[:key]}][#{action}]', 'profile[permissions][#{resource[:key]}][scope]')
    expect(profiles_form_view).to include("current_tenant.profiles.ordered_vertical", "profile_admin_toggle", "ax_sticky_action_footer")
    expect(profiles_form_view).to include('<caption class="tw-sr-only">', 'scope="col"', 'scope="row"', 'aria: { label: "Escopo de')
    expect(stylesheet).to include(".prof-matrix__resource-col", ".prof-matrix__action-col", ".prof-matrix__scope-col")
    expect(stylesheet).to include('.prof-matrix tbody th[scope="row"]', "grid-template-columns: 26px minmax(0, 1fr)")
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.prof-matrix tbody th/)
    expect(stylesheet).to include('html[data-admin-theme="dark"] .prof-fullaccess', 'html[data-admin-theme="dark"] .prof-fullaccess__toggle strong')
    expect(stylesheet).to match(/@media \(min-width:\s*1080px\)[^{]*\{[\s\S]*?\.prof-grid/)
  end

  it "evita contagens N mais 1 e compartilha as acoes da listagem de perfis" do
    controller = File.read(File.expand_path("../../../app/controllers/admin/profiles_controller.rb", __dir__))
    index_view = File.read(File.expand_path("../../../app/views/admin/profiles/index.html.erb", __dir__))
    show_view = File.read(File.expand_path("../../../app/views/admin/profiles/show.html.erb", __dir__))

    expect(controller).to include("@users_count_by_profile_id = profile_user_counts", ".group(:profile_id)", ".group(:horizontal_profile_id)")
    expect(index_view).to include("@users_count_by_profile_id.fetch(profile.id, 0)", "ax_icon_button(", '<caption class="tw-sr-only">')
    expect(index_view).not_to include("profile.admin_users.where(tenant: current_tenant).count")
    expect(show_view).to include("ax_operational_panel(", 'scope="row"', "Resumo estrutural do perfil")
  end

  it "compoe o painel do sistema sem geometria inline e preserva acoes privilegiadas" do
    expect(system_index_view).not_to match(/\bstyle\s*=/i)
    expect(system_index_view).to include("ax_metric_card(", "ax_operational_panel(", "ax_empty_state(")
    expect(system_index_view).to include("ax-system-login-release-field", "ax-table__col--w-120")
    expect(system_index_view).to include("admin_system_login_rate_limit_reset_path", "admin_system_tenant_owner_impersonation_path(tenant)", 'link_to("Abrir Mission Control", "/jobs"')
    expect(system_index_view).to include('form.email_field :email', "@failed_job_groups", "@system_admins")
    expect(system_index_view).to include("@tenant_owners_by_tenant_id[tenant.id]", '<caption class="tw-sr-only">', 'scope="col"')
    expect(system_users_view).to include('<caption class="tw-sr-only">', 'scope="col"')
    system_stylesheet = File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/system_workspace.css", __dir__))
    expect(system_stylesheet).to include('[data-admin-theme="dark"] .ax-system', "var(--ax-dark-danger-surface)", "@media (max-width: 560px)")
    expect(stylesheet).to match(/\.ax-system-login-release-field\s*\{[^}]*min-width:\s*min\(100%, 360px\);/m)
  end

  it "compoe a integracao Meta com painel e estado vazio compartilhados" do
    expect(meta_integrations_index_view).not_to match(/\bstyle\s*=/i)
    expect(meta_integrations_index_view).to include("ax_workspace_heading(", "ax_operational_panel(", "ax_empty_state(")
    expect(meta_integrations_index_view).to include("ax_record_item(", "ax-disclosure-card", "ax-spinner")
    expect(meta_integrations_index_view).not_to include('class="ax-card', 'class="ax-empty')
    expect(meta_integrations_index_view).to include("meta-integration-account", "meta-integration-avatar--page", "meta-integration-connect-icon")
    expect(meta_integrations_index_view).to include("turbo_stream_from", "disconnect_admin_meta_integrations_path", "sync_pages_admin_meta_integrations_path", "list_forms_admin_meta_integrations_path")
    expect(meta_integrations_index_view).to include("admin_user_facebook_omniauth_authorize_path", 'data: { turbo: false }')
    meta_forms_view = File.read(File.expand_path("../../../app/views/admin/meta_integrations/list_forms.html.erb", __dir__))
    expect(meta_forms_view).to include("ax_record_item(", "ax_empty_state(", "ax-spinner")
    expect(meta_forms_view).not_to include("list-unstyled", "spinner-border", "border-bottom-dashed", "visually-hidden")
    expect(stylesheet).to include(".meta-integration-avatar--page", ".meta-integration-connect-icon")
    expect(stylesheet).not_to include(".meta-integration-avatar--account")
  end

  it "compoe acessos externos com grid e clipboard compartilhados" do
    expect(account_memberships_index_view).not_to match(/\bstyle\s*=|\bonclick\s*=/i)
    expect(account_memberships_index_view).to include("ax_workspace_heading(", "ax_field_grid do", "ax_operational_panel(", "ax_empty_state(")
    expect(account_memberships_index_view).to include("ax-span-6", "ax-span-4", 'data-controller="clipboard"', 'data-action="clipboard#copy"', 'click->clipboard#select')
    expect(account_memberships_index_view).to include(":invited_email", 'account_membership[access_profile_id]', ":acting_type", ":manager_id", ":rentals_manager_id")
    expect(account_memberships_index_view).to include("admin_account_membership_path(m)", "turbo_confirm:", "m.invite_expired?", "m.revoked?")
    expect(account_memberships_index_view).to include('for: "account_membership_access_profile_id"', 'id: "account_membership_access_profile_id"')
  end

  it "compoe o editor de proprietario com cadastro e portfolio densos" do
    expect(proprietors_edit_view).not_to match(/\bstyle\s*=/i)
    expect(proprietors_edit_view).not_to include("<style>", "bg-light", "text-dark", "border-end", "border-top")
    expect(proprietors_edit_view).to include("ax_workspace_heading(", "ax_operational_panel(", "ax_field_grid do", "ax_empty_state(")
    expect(proprietors_edit_view).to include("ax_badge(", 'class: "ax-ico-btn"', "ax_pagination @linked_habitations")
    expect(proprietors_edit_view).to include(":habitation_q", ":habitation_status", "admin_habitation_internal_path(habitation)", "habitation_path(habitation)")
    expect(stylesheet).to include(".proprietor-property", '.proprietor-property__facts', '[data-admin-theme="dark"] .proprietor-property')
    expect(stylesheet).to match(/@media \(max-width: 639px\)[\s\S]*?\.proprietor-property__facts/)
  end

  it "compartilha o contrato do formulario entre cadastro e edicao de proprietarios" do
    new_view, edit_view, form_view = proprietor_form_views
    combined_view = proprietor_form_views.join("\n")

    expect(combined_view).not_to match(/\bstyle\s*=/i)
    expect(combined_view).not_to include("<style>", "bg-light", "bg-light-subtle", "img-thumbnail", "border-top")
    expect(new_view).to include("ax_workspace_heading(", "ax_operational_panel(", 'render \'form\', proprietor: @proprietor')
    expect(edit_view).to include('render "form", proprietor: @proprietor')
    expect(form_view).to include("ax_field_grid do", "ax_field_group(", "ax_toggle_chip(", "ax_input_group(", "ax_file_field(", "ax_form_actions(")
    expect(form_view.scan(/ax_text_field\(/).size).to eq(23)
    expect(form_view.scan(/ax_select_field\(/).size).to eq(6)
    expect(form_view.scan(/ax_date_field\(/).size).to eq(2)
    expect(form_view.scan(/f\.(?:label|select|email_field|date_field|text_area)/).size).to eq(0)
    expect(form_view.scan(/f\.text_field/).size).to eq(1)
    expect(form_view).to include('data-controller="cep-search"', 'controller: "phone-input"', 'controller: "tom-select"', 'controller: "mask"')
    expect(form_view).to include(":name", ":role", ":cpf_cnpj", ":email", ":cep", ":spouse_name", ":notes", ":profile_image")
    expect(stylesheet).to include(".proprietor-form__avatar-preview", '[data-admin-theme="dark"] .proprietor-form__avatar-preview')
  end

  it "compoe landing pages com conteudo, filtros e preview compartilhados" do
    new_view, edit_view, form_view = landing_page_form_views
    combined_view = landing_page_form_views.join("\n")

    expect(combined_view).not_to match(/\bstyle\s*=/i)
    expect(combined_view).not_to include('class="ax-card', "custom-checkbox-card", "form-check", "spinner-border")
    expect(new_view).to include("ax_workspace_heading(", "render 'form'")
    expect(edit_view).to include("ax_workspace_heading(", "render 'form'")
    expect(form_view.scan(/ax_operational_panel\(/).size).to eq(3)
    expect(form_view).to include("ax_error_summary(", "ax_input_group(", "ax_field_group(", "ax_chip_grid do", "ax_toggle_chip(", "ax_switch_field(", "ax_form_actions(")
    expect(form_view.scan(/ax_text_field\(/).size).to eq(6)
    expect(form_view.scan(/ax_autocomplete_select_field\(/).size).to eq(3)
    expect(form_view.scan(/ax_select_field\(/).size).to eq(1)
    expect(form_view.scan(/ax_number_field\(/).size).to eq(4)
    expect(form_view.scan(/ax_measure_field\(/).size).to eq(1)
    expect(form_view.scan(/(?:f|fp)\.(?:label|select|text_area|number_field)/).size).to eq(0)
    expect(form_view.scan(/f\.text_field/).size).to eq(1)
    expect(form_view).to include('controller: "property-page-preview"', 'data-property-page-preview-target="count"', 'data-property-page-preview-target="results"', 'aria-live="polite"', 'aria-busy="true"')
    expect(form_view).to include('name: "landing_page[filter_params][characteristics][]"', "include_hidden: false", 'change->property-page-preview#refresh', "@property_categories", "@property_cities", "@property_neighborhoods")
    expect(stylesheet).to include(".landing-page-preview", ".landing-page-preview__count", ".landing-page-preview__loading", ".landing-page-preview__actions", ".landing-page-preview__hero", ".landing-page-preview__stat", ".landing-page-preview__progress", ".landing-page-preview__empty")
    expect(stylesheet).to match(/@media \(max-width: 900px\)[\s\S]*?\.landing-page-preview \{ position: static; \}/)
    expect(property_page_preview_controller).to include('new AbortController()', 'escapeHtml(value)', 'class="landing-page-preview__progress"', 'role="alert"', 'this.countTarget.hidden = false', 'this.resultsTarget.setAttribute("aria-busy", "false")')
    expect(property_page_preview_controller).not_to include("console.log", "alert alert-danger", "text-center py-5", "preview-stat-card", 'style="')
  end

  it "mantem a listagem de landing pages sem geometria inline" do
    expect(landing_pages_index_view).not_to match(/\bstyle\s*=/i)
    expect(landing_pages_index_view).to include("ax_workspace_heading(", 'class="ax-table-wrap"')
    expect(landing_pages_index_view).to include("ax-table__col--w-220", "ax-table__col--sm", "ax-table__col--compact")
    expect(landing_pages_index_view).to include("public_landing_page_path(page.slug)", "edit_admin_landing_page_path(page)", "admin_landing_page_path(page)")
    expect(landing_pages_index_view).to include("ax_pagination @landing_pages", "turbo_confirm:")
  end

  it "mantem os skeletons do dashboard no contrato CSS sem geometria inline" do
    expect(dashboard_loading_panel_view).not_to match(/\bstyle\s*=/i)
    expect(dashboard_loading_panel_view).to include('role="status"', 'aria-live="polite"', 'aria-busy="true"', 'aria-label="Carregando <%= title %>"')
    expect(dashboard_loading_panel_view).to include('class="ax-skeleton-chart" aria-hidden="true"', "7.times do")
    expect(dashboard_loading_panel_view).to include('class="ax-skeleton-table" aria-hidden="true"', 'class="ax-skeleton-list" aria-hidden="true"', 'class="ax-skeleton-row"')
    expect(dashboard_loading_panel_view).to include('ax-skeleton-row__line--<%= (index % 5) + 1 %>')
    (1..7).each { |index| expect(loading_stylesheet).to include(".ax-skeleton-chart span:nth-child(#{index})") }
    (1..5).each { |index| expect(loading_stylesheet).to include(".ax-skeleton-row__line--#{index}") }
    expect(loading_stylesheet).to include("@keyframes ax-skeleton-sheen", "@media (prefers-reduced-motion: reduce)")
    expect(loading_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-skeleton-chart\s*\{/)
    expect(stylesheet).not_to match(/(?:^|\n)\.ax-(?:dashboard-skeleton|skeleton-(?:pill|row|chart|table|list))/)
    expect(stylesheet).not_to include("@keyframes ax-skeleton-sheen")
  end


  it "mantem o composer compartilhado sem cores inline e com contratos de interacao" do
    expect(whatsapp_composer_view).not_to match(/\bstyle\s*=/i)
    expect(whatsapp_composer_view.scan(/wa-composer-popover__icon--/).size).to eq(7)
    expect(whatsapp_composer_view).to include("wa-composer-popover__icon--document", "wa-composer-popover__icon--media", "wa-composer-popover__icon--camera", "wa-composer-popover__icon--audio")
    expect(whatsapp_composer_view).to include("wa-composer-popover__icon--presentation", "wa-composer-popover__icon--edit", "wa-composer-popover__icon--template")
    expect(whatsapp_composer_view).to include('controller: "wa-composer"', 'data-controller="attach-menu"', 'data-controller="emoji-picker"', 'data-controller="quick-replies"')
    expect(whatsapp_composer_view).to include('data-wa-composer-target="fileInput"', 'data-wa-composer-target="body"', 'data-wa-composer-target="submit"', 'data-wa-composer-target="recordingBar"')
    %w[document media camera audio presentation edit template].each do |tone|
      expect(whatsapp_inbox_stylesheet).to include(".wa-composer-popover__icon--#{tone}")
    end
    expect(whatsapp_inbox_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.wa-composer-popover__icon--document/)
    expect(whatsapp_inbox_stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.wa-composer-popover__icon--edit/)
  end

  it "aplica o contrato dark dos menus do WhatsApp na inbox e no detalhe do lead" do
    shared_dark_scope = /html\[data-admin-theme=["']dark["']\] :is\(\.wa-inbox-page, \.lead-whatsapp-card\)/

    expect(whatsapp_inbox_stylesheet).to match(shared_dark_scope)
    expect(whatsapp_inbox_stylesheet).to match(/#{shared_dark_scope.source} \.wa-msg-menu/)
    expect(whatsapp_inbox_stylesheet).to match(/#{shared_dark_scope.source} \.wa-composer-popover/)
    expect(whatsapp_inbox_stylesheet).to match(/#{shared_dark_scope.source} \.wa-forward-modal__panel/)
    expect(whatsapp_inbox_stylesheet).to match(/\.wa-forward-modal__list > button:focus-visible/)
    expect(whatsapp_inbox_stylesheet).to match(/\.wa-composer-popover--menu > button:focus-visible/)
    expect(whatsapp_inbox_stylesheet).to match(/\.wa-emoji-popover button:focus-visible/)
    expect(whatsapp_inbox_stylesheet).not_to match(
      /html\[data-admin-theme=["']dark["']\] \.lead-whatsapp-card \.wa-(?:msg-menu|composer-popover|emoji-popover)/
    )
  end


  it "mantem os paineis compartilhados do registro do imovel no contrato dark" do
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-property-record-panel/m)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-property-show-price/m)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-property-stat/m)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-property-record-section__head/m)
    expect(stylesheet).to match(/\.ax-property-show-price--discounted\s*\{[^}]*--ax-dark-success-surface/m)
  end


  it "mantem o resumo CRM e o gerenciador de cartoes legiveis no dark" do
    presentation_card_stylesheet = File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/presentation_cards.css", __dir__))

    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.wa-inbox-thread__crm-disclosure/m)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.wa-inbox-thread__crm-card/m)
    expect(stylesheet).to match(/(?:html)?\[data-admin-theme=["']dark["']\] \.wa-inbox-thread__scroll\s*\{/)
    expect(presentation_card_stylesheet).to match(/\[data-admin-theme=["']dark["']\] \.pc-item\s*\{/)
    expect(presentation_card_stylesheet).to match(/\[data-admin-theme=["']dark["']\] \.pc-item__delete:hover\s*\{/)
    expect(presentation_card_stylesheet).to match(/\[data-admin-theme=["']dark["']\] \.pc-item__new-trigger:hover\s*\{/)
    expect(stylesheet).not_to match(/(?:^|\n)\.pc-(?:manager|item)/)
  end

  it "centraliza barras e geometria do dashboard sem estilos inline" do
    rankings_view, support_view, funnel_view = dashboard_operational_views

    expect(dashboard_operational_views.join("\n")).not_to match(/\bstyle\s*=/i)
    expect(rankings_view.scan(/ax_progress\(/).size).to eq(2)
    expect(support_view.scan(/ax_progress\(/).size).to eq(1)
    expect(funnel_view).not_to include("--stage-width", "--stage-index", "row[:width]")
    expect(dashboard_controller).not_to match(/tone:\s*"(?:red|orange|amber|blue)",\s*width:/)
    expect(stylesheet).to include(
      ".ax-dashboard-rank__progress.ax-progress",
      ".ax-dashboard-category__progress.ax-progress",
      ".ax-dashboard-funnel__stage:nth-child(1) { --stage-index: 0; width: 100%; }",
      ".ax-dashboard-funnel__stage:nth-child(4) { --stage-index: 3; width: 46%; }"
    )
  end

  it "compoe cadastro e edicao de propostas com os contratos compartilhados" do
    new_view, edit_view, form_view = proposal_form_views
    combined_view = proposal_form_views.join("\n")

    expect(combined_view).not_to match(/\bstyle\s*=/i)
    expect(new_view).to include("ax_workspace_heading(", "Nova proposta", "Voltar ao lead")
    expect(edit_view).to include("ax_workspace_heading(", "pills: [@proposal.status_label]", "Voltar ao lead")
    expect(form_view).to include(
      "ax_error_summary(proposal",
      "ax_operational_panel(",
      "ax_field_grid do",
      "ax_currency_field(",
      "ax_date_field(",
      "ax_form_actions("
    )
    expect(form_view.scan(/ax_currency_field\(/).size).to eq(2)
    expect(form_view).to include('data: { controller: "tom-select" }', 'scope: :proposal')
  end

  it "usa utilitarios compartilhados nos residuos fixos de layouts operacionais" do
    access_view, dwv_view, error_events_view, admin_user_view, store_shift_view = fixed_layout_residue_views

    expect(fixed_layout_residue_views.join("\n")).not_to match(/\bstyle\s*=/i)
    expect(access_view).to include('class="tw-flex-1 tw-min-w-0"')
    expect(dwv_view).to include('<th class="ax-table__col--w-120">Ocorrências</th>')
    expect(error_events_view).to include('class="ax-num ax-table__col--compact">Ação</th>')
    expect(admin_user_view).to include('ax-dashboard-panel__link tw-mt-2 tw-inline-block')
    expect(store_shift_view).to include('class="ax-card tw-mb-2"', "tw-gap-2 tw-mb-0")
    expect(store_shift_view).not_to match(/\bbg-light\b/)
    expect(table_stylesheet).to include(
      ".ax-table__col--compact { width: 90px; }",
      ".ax-table__col--w-120 { width: 120px; }"
    )
  end

  it "aplica a preferencia individual de tema sem depender de recarga" do
    controller = File.read(File.expand_path("../../../app/javascript/controllers/theme_preference_controller.js", __dir__))
    admin_layout = File.read(File.expand_path("../../../app/views/layouts/admin.html.erb", __dir__))
    field_home = File.read(File.expand_path("../../../app/views/field/home/show.html.erb", __dir__))

    expect([admin_layout, field_home].join("\n").scan(/controller: "theme-preference"/).size).to eq(2)
    expect([admin_layout, field_home].join("\n").scan(/submit->theme-preference#submit/).size).to eq(2)
    expect(controller).to include(
      'root.dataset.adminTheme = mode',
      'root.dataset.fieldTheme = mode',
      'root.style.setProperty(`--${name.replaceAll("_", "-")}`, value)',
      'meta[name="theme-color"]',
      'modeInput.value = dark ? "light" : "dark"',
      'theme-preference:changed'
    )
    expect(controller).to include('Accept: "application/json"', 'credentials: "same-origin"', 'this.element.submit()')
  end

  it "mantem as matrizes documentais completas e alinhadas ao inventario real" do
    component_files = Dir[File.expand_path("../../../app/assets/stylesheets/admin/components/*.css", __dir__)]
      .map { |path| File.basename(path) }
      .sort
    component_section = dark_theme_progress_report[/## Matriz objetiva por componente.*?Leitura objetiva da matriz:/m]

    expect(component_section).not_to be_nil

    reported_components = component_section.lines.filter_map do |line|
      line[/^\| .*?\| `([^`]+\.css)` \|/, 1]
    end.sort

    expect(reported_components).to eq(component_files)
    expect(reported_components.size).to eq(69)

    family_section = dark_theme_progress_report[/## Matriz de homologação visual por família.*?## Roteiro mínimo de smoke por família/m]

    expect(family_section).not_to be_nil

    family_rows = family_section.lines.select do |line|
      line.start_with?("| ") && !line.start_with?("| ---")
    end.drop(1)
    family_names = family_rows.map { |row| row.split("|")[1].strip }

    expect(family_rows.size).to eq(19)
    expect(family_rows).to all(satisfy { |row| row.count("|") == 9 && row.include?("Em validação") })
    expect(family_names).to eq(family_names.uniq)
    expect(dark_theme_progress_report).to include("0/19 famílias concluídas", "0 ocorrências em 0 arquivos")
  end

  it "mantem um roteiro minimo de smoke para cada familia visual" do
    family_section = dark_theme_progress_report[/## Matriz de homologação visual por família.*?## Roteiro mínimo de smoke por família/m]
    smoke_section = dark_theme_progress_report[/## Roteiro mínimo de smoke por família.*?## Telas que já receberam/m]

    expect(family_section).not_to be_nil
    expect(smoke_section).not_to be_nil

    family_names = family_section.lines.filter_map do |line|
      next if line.start_with?("| ---")

      line[/^\| ([^|]+) \|/, 1]&.strip
    end.drop(1)
    smoke_rows = smoke_section.lines.filter_map do |line|
      match = line.match(/^\| ([^|]+) \| (`\/admin[^`]*`) \| (`\/admin[^`]*`) \| ([^|]+) \|$/)
      next unless match

      {
        family: match[1].strip,
        base_route: match[2],
        complementary_route: match[3],
        states: match[4].strip
      }
    end

    expect(smoke_rows.size).to eq(19)
    expect(smoke_rows.map { |row| row[:family] }).to eq(family_names)
    expect(smoke_rows.map { |row| row[:family] }).to eq(smoke_rows.map { |row| row[:family] }.uniq)
    expect(smoke_rows).to all(satisfy do |row|
      row[:base_route].start_with?("`/admin") &&
        row[:complementary_route].start_with?("`/admin") &&
        row[:states].split(",").size >= 4
    end)
    expect(smoke_section).to include("tenant corrente", "Ações destrutivas")
  end

  it "sincroniza a cor da moldura PWA com o tema efetivo dos layouts administrativos" do
    admin_layout = File.read(File.expand_path("../../../app/views/layouts/admin.html.erb", __dir__))
    wizard_layout = File.read(File.expand_path("../../../app/views/layouts/captacao_wizard.html.erb", __dir__))
    pwa_meta = File.read(File.expand_path("../../../app/views/layouts/_pwa_meta.html.erb", __dir__))

    expect(admin_layout).to include(
      "current_admin_user&.effective_admin_theme_mode",
      "effective_admin_theme(mode: admin_theme_mode)",
      "render 'layouts/pwa_meta', theme_color: admin_theme[:header]"
    )
    expect(admin_layout.scan(/render 'layouts\/pwa_meta'/).size).to eq(1)
    expect(admin_layout).not_to match(/<meta name="theme-color"/)
    expect(wizard_layout).to include(
      "current_admin_user&.effective_admin_theme_mode",
      "effective_admin_theme(mode: admin_theme_mode)",
      '<meta name="theme-color" content="<%= admin_theme[:header] %>">',
      '--admin-primary: <%= admin_theme[:primary] %>',
      "border-color: var(--admin-primary)",
      "background: var(--admin-primary)"
    )
    expect(pwa_meta).to include("local_assigns.fetch(:theme_color, '#022B3A')")
    expect(pwa_meta.scan(/<meta name="theme-color"/).size).to eq(1)
    expect(admin_layout).not_to include('content="#ffffff"')
    expect(wizard_layout).not_to include("#0d6efd")
    expect(wizard_layout).not_to match(/rgba\(13,\s*110,\s*253/)
  end

  it "remove o azul Bootstrap dos focos compartilhados e da instalacao do Field" do
    admin_stylesheet = File.read(File.expand_path("../../../app/assets/stylesheets/admin.css", __dir__))
    field_layout = File.read(File.expand_path("../../../app/views/layouts/field.html.erb", __dir__))
    field_views = Dir[File.expand_path("../../../app/views/field/**/*.erb", __dir__)].map { |path| File.read(path) }

    expect(admin_stylesheet).to include(
      ".ts-wrapper.focus .ts-control",
      "color-mix(in srgb, var(--admin-primary) 25%, transparent)"
    )
    expect(field_layout).to include(
      "field_primary_color =",
      "--field-primary: <%= field_primary_color %>",
      "color-mix(in srgb, var(--field-primary) 12%, transparent)",
      "color-mix(in srgb, var(--field-primary) 82%, #000)"
    )
    expect(field_layout).to include(
      "current_admin_user&.effective_admin_theme_mode",
      "data-field-theme",
      'stylesheet_link_tag "field_theme"'
    )
    expect(field_layout).not_to include("LayoutSetting.instance.admin_theme_mode", "data-admin-theme")
    expect(field_views).to all(satisfy { |view| !view.match?(/\sstyle\s*=/i) })
    expect([admin_stylesheet, field_layout].join("\n")).not_to match(
      /#0d6efd|#0a58ca|rgba\(13,\s*110,\s*253/i
    )
  end

  it "mantem o voltar do breadcrumb alinhado ao tema efetivo em light e dark" do
    breadcrumb_back = stylesheet[/\.ax-breadcrumb__back\s*\{.*?\n\}/m]
    breadcrumb_back_hover = stylesheet[/\.ax-breadcrumb__back:hover\s*\{.*?\n\}/m]

    expect(breadcrumb_back).to include("color: var(--admin-primary, #365f8f) !important")
    expect(breadcrumb_back_hover).to include(
      "color: color-mix(in srgb, var(--admin-primary, #365f8f) 82%, #000) !important"
    )
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-breadcrumb__back\s*\{/)
    expect(stylesheet).to match(/data-admin-theme=["']dark["'][^{]*\.ax-breadcrumb__back:hover\s*\{/)
  end

  it "aplica a identidade do tenant nos estados operacionais do WhatsApp" do
    expect(stylesheet).to include(
      ".wa-audio-preview__toggle",
      "background: var(--admin-primary, #365f8f)",
      "color-mix(in srgb, var(--admin-primary, #365f8f) 82%, #000)",
      ".wa-inbox-media-card__icon",
      "color-mix(in srgb, var(--admin-primary, #365f8f) 8%, transparent)",
      ".whatsapp-selected-group .ax-btn--primary",
      ".whatsapp-campaign-builder__progress > span",
      ".whatsapp-schedule-mode.is-selected",
      "color-mix(in srgb, var(--admin-primary, #365f8f) 12%, transparent)",
      ".whatsapp-schedule-mode__icon--scheduled",
      ".whatsapp-template-variable-row__token",
      ".whatsapp-campaign-template-preview__media--placeholder"
    )
  end

  it "mantem banners e estados estaticos dos shells fora de estilos inline" do
    admin_layout = File.read(File.expand_path("../../../app/views/layouts/admin.html.erb", __dir__))
    admin_push = File.read(File.expand_path("../../../app/views/layouts/_admin_push_subscriptions.html.erb", __dir__))
    field_layout = File.read(File.expand_path("../../../app/views/layouts/field.html.erb", __dir__))
    menu_component = File.read(File.expand_path("../../../app/assets/stylesheets/admin/components/menu.css", __dir__))
    shell_sources = [admin_layout, admin_push, field_layout]

    expect(shell_sources.join("\n")).not_to match(/\bstyle\s*=/i)
    expect([admin_push, field_layout].join("\n")).not_to include("style.cssText")
    expect(admin_layout).to include(
      "ax-menu ax-menu--end",
      "ax-menu__item ax-menu__item--current",
      "ax-admin-offline-banner"
    )
    expect(admin_push).to include(
      'banner.className = "ax-push-permission-banner"',
      "ax-push-permission-banner__enable",
      "ax-push-permission-banner__dismiss"
    )
    expect(field_layout).to include(
      'banner.className = "field-push-banner"',
      'class="field-offline-banner"',
      'class="field-install-overlay"',
      'class="field-ptr"'
    )
    expect(stylesheet).to include(".ax-admin-offline-banner", ".ax-push-permission-banner")
    expect(menu_component).to include(".ax-menu__item--current")
  end

  it "compartilha o workspace de audiencias entre importados e descadastros" do
    recipients_view = File.read(
      File.expand_path("../../../app/views/admin/whatsapp_campaign_recipients/index.html.erb", __dir__)
    )
    unsubscribes_view = File.read(
      File.expand_path("../../../app/views/admin/whatsapp_campaign_unsubscribes/index.html.erb", __dir__)
    )
    audience_stylesheet = File.read(
      File.expand_path("../../../app/assets/stylesheets/admin/components/audience_workspace.css", __dir__)
    )

    expect([recipients_view, unsubscribes_view].join("\n")).not_to include("<style")
    expect(recipients_view).to include(
      'class="ax-audience-workspace"',
      "ax-audience-workspace__summary--4",
      "ax-audience-workspace__filters--5",
      "ax-audience-workspace__tag"
    )
    expect(unsubscribes_view).to include(
      'class="ax-audience-workspace"',
      "ax-audience-workspace__summary--3",
      "ax-audience-workspace__filters--4",
      "ax-audience-workspace__reenable"
    )
    expect(audience_stylesheet).to include(
      '[data-admin-theme="dark"] .ax-audience-workspace__tag',
      ".ax-audience-workspace__summary--4",
      ".ax-audience-workspace__filters--5",
      "@media (max-width: 900px)"
    )
  end

  it "mantem os estados da integracao Meta acessiveis e sem spinner legado" do
    sync_status = File.read(
      File.expand_path("../../../app/views/admin/meta_integrations/_sync_status.html.erb", __dir__)
    )
    forms = File.read(
      File.expand_path("../../../app/views/admin/meta_integrations/list_forms.html.erb", __dir__)
    )

    expect(sync_status).to include(
      'role="status"',
      'aria-live="polite"',
      'class="ax-spinner"',
      'label: "Sincronização Meta:'
    )
    expect(sync_status).not_to include("fa-spin")
    expect(forms).not_to include("frame_id:")
  end

  it "organiza a busca inteligente por grupos funcionais responsivos" do
    view = File.read(File.expand_path("../../../app/views/admin/property_settings/edit.html.erb", __dir__))

    expect(view).to include(
      'class_name: "property-settings-ai-search-group"',
      'title: "Recursos da busca"',
      'title: "Interpretação e mensagens"',
      'title: "Consulta e limites"',
      'class="property-settings-ai-metrics"',
      'title: "Nenhum alias cadastrado"'
    )
    expect(stylesheet).to include(
      ".property-settings-ai-search-groups { display: grid; gap: 12px; }",
      ".property-settings-ai-metrics { display: grid; grid-template-columns: repeat(auto-fit, minmax(145px, 1fr));"
    )
  end

  it "mantem identidade da conta separada do tema pessoal na configuracao visual" do
    expect(layout_settings_edit_view).to include(
      "ax_workspace_heading(",
      'title: "Identidade e Marca"',
      '"Escopo: conta"',
      '"Tema pessoal:',
      "Cada usuário continua escolhendo individualmente"
    )
    expect(layout_settings_edit_view).to include('class: "ax-control layout-settings-interest__textarea"')
    expect(stylesheet).to include(
      'html[data-admin-theme="dark"] .layout-settings-interest__toggle',
      'html[data-admin-theme="dark"] .layout-settings-interest__weights',
      ".layout-settings-interest__toggle:focus-within",
      "@media (max-width: 1100px)"
    )
  end

  it "remove superficies claras e inicializa tabs acessiveis nas configuracoes da Home" do
    expect(home_settings_edit_view).to include(
      'aria-controls="hero" aria-selected="true" tabindex="0"',
      'aria-controls="cta" aria-selected="false" tabindex="-1"',
      'id="cta" role="tabpanel" aria-labelledby="cta-tab" aria-hidden="true" tabindex="0" hidden',
      'class="home-settings-slide-item"',
      'class="ax-form-tabs__panels"',
      'class="ax-form-tabs__panel"',
      "ax_empty_state(",
      "ax_sticky_action_footer("
    )
    expect(home_settings_edit_view).not_to include("bg-white", "bg-light")
    expect(stylesheet).to include(
      ".home-settings-slide-item__content",
      'html[data-admin-theme="dark"] .home-settings-slide-item',
      "@media (max-width: 760px)"
    )
  end
end
