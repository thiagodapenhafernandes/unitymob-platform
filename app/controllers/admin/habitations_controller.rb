class Admin::HabitationsController < Admin::BaseController
  HABITATIONS_FILTER_SESSION_MAX_ARRAY_ITEMS = 20
  HABITATIONS_FILTER_SESSION_MAX_VALUE_LENGTH = 180

  include RentalGuaranteeParamNormalizer

  before_action -> { check_permission!(:view, :imoveis) }
  before_action -> { check_permission!(:create, :imoveis) }, only: [:new, :create, :duplicate]
  before_action :authorize_data_export!, only: [:print, :export, :exports, :export_status, :download_export, :destroy_export]
  before_action :authorize_bulk_publish!, only: [:bulk_publish, :bulk_publish_eligibility, :share_selection]
  before_action :scope_habitations_by_permission, only: [:edit, :update, :destroy, :duplicate, :operational_hub, :gallery, :confirm_owner_contact, :purge_attachment, :generate_ai_preview, :format_ai_suggestion, :apply_ai_suggestion]
  require "csv"
  require "uri"

  REPORT_TYPES = {
    "visit_sheet" => "Ficha de visita",
    "capture_sheet_commercial" => "Ficha de captação - Imóveis comerciais",
    "capture_sheet_residential" => "Ficha de captação - Imóveis residenciais",
    "capture_sheet_land" => "Ficha de captação - Terrenos",
    "photos_sheet" => "Lista de fotos",
    "client_sheet_commercial" => "Lista para clientes - Imóveis comerciais",
    "client_sheet_residential" => "Lista para clientes - Imóveis residenciais",
    "client_sheet_land" => "Lista para clientes - Terrenos",
    "vitrine_sheet" => "Lista vitrine",
    "sale_rent_total_values" => "Resumo de valores de venda e aluguel",
    "property_list" => "Listagem de imóveis",
    "property_list_with_m2" => "Listagem de imóveis com valor do m²",
    "property_list_by_broker" => "Listagem de imóveis por corretor",
    "property_count_by_broker" => "Resumo de imóveis por corretor"
  }.freeze
  REPORT_GROUPS = {
    "Fichas" => %w[visit_sheet capture_sheet_commercial capture_sheet_residential capture_sheet_land],
    "Listas e resumos" => %w[
      photos_sheet
      client_sheet_commercial
      client_sheet_residential
      client_sheet_land
      vitrine_sheet
      sale_rent_total_values
      property_list
      property_list_with_m2
      property_list_by_broker
      property_count_by_broker
    ]
  }.freeze
  REPORT_PAGE_SIZE = {
    "visit_sheet" => 1,
    "capture_sheet_commercial" => 1,
    "capture_sheet_residential" => 1,
    "capture_sheet_land" => 1,
    "property_list" => 24,
    "property_list_with_m2" => 24,
    "property_list_by_broker" => 14
  }.freeze
  INDEX_PAGE_SIZE_OPTIONS = [10, 20].freeze
  DEFAULT_INDEX_PAGE_SIZE = 10
  DASHBOARD_QUALITY_FILTERS = %w[missing_address missing_photos missing_price stale].freeze
  REPORT_MAX_PAGES = 100
  DEFAULT_CATALOG_STATUSES = ["Venda", "Aluguel", "Diária"].freeze
  DEFAULT_CODIGO_SORT_SQL = "CASE WHEN (habitations.codigo ~ '^[0-9]+$') THEN habitations.codigo::bigint ELSE 0 END".freeze
  # Fonte única dos campos de exportação vive no service (reusado pelo job async).
  EXPORT_FIELDS = Habitations::CsvExporter::FIELDS
  RETURN_PARAM_DENYLIST = %w[
    controller action id habitation_id return_to back_anchor authenticity_token _method utf8 commit
    habitation save_anchor save_navigation save_context release_to_broker_after_save save_internal_after_save
    association attachment_id
  ].freeze
  LATEST_HUMAN_ACTIVITY_SQL = <<~SQL.squish.freeze
    COALESCE(
      (
        SELECT MAX(habitation_audit_logs.created_at)
        FROM habitation_audit_logs
        WHERE habitation_audit_logs.habitation_id = habitations.id
          AND habitation_audit_logs.tenant_id = habitations.tenant_id
          AND habitation_audit_logs.source IN ('admin', 'captacao')
      ),
      habitations.data_cadastro_crm,
      habitations.created_at
    )
  SQL
  SORT_OPTIONS = {
    "data_cadastro_crm" => { label: "Última atividade", column: LATEST_HUMAN_ACTIVITY_SQL, default_direction: "desc" },
    "codigo" => { label: "Código mais recente", column: DEFAULT_CODIGO_SORT_SQL, default_direction: "desc" },
    "categoria" => { label: "Categoria", column: "categoria", default_direction: "asc" },
    "endereco" => { label: "Endereço", column: "endereco", default_direction: "asc" },
    "numero" => { label: "Endereço número", column: "numero", default_direction: "asc" },
    "complemento" => { label: "Endereço complemento", column: "complemento", default_direction: "asc" },
    "dormitorios_qtd" => { label: "Dormitório", column: "dormitorios_qtd", default_direction: "desc" },
    "valor_venda_cents" => { label: "Valor venda", column: "valor_venda_cents", default_direction: "desc" },
    "valor_locacao_cents" => { label: "Valor aluguel", column: "valor_locacao_cents", default_direction: "desc" },
    "bairro_comercial" => { label: "Bairro comercial", column: "bairro_comercial", default_direction: "asc" },
    "nome_empreendimento" => { label: "Empreendimento", column: "nome_empreendimento", default_direction: "asc" },
    "valor_m2_aluguel" => { label: "Valor M2 aluguel", column: "valor_por_m2_cents", default_direction: "desc" },
    "valor_por_m2_cents" => { label: "Valor M2 venda", column: "valor_por_m2_cents", default_direction: "desc" },
    "valor_total_aluguel_cents" => { label: "Valor total aluguel", column: "valor_total_aluguel_cents", default_direction: "desc" }
  }.freeze

  before_action :set_habitation, only: [:show, :edit, :update, :destroy, :duplicate, :operational_hub, :gallery, :confirm_owner_contact, :generate_ai_preview, :format_ai_suggestion, :apply_ai_suggestion]
  before_action :prepare_habitation_address, only: [:show, :edit, :operational_hub]
  before_action :prepare_legacy_habitation_address, only: [:update]
  before_action :authorize_habitation_edit!, only: [:edit, :update]
  before_action :authorize_habitation_ai_content!, only: [:generate_ai_preview, :format_ai_suggestion, :apply_ai_suggestion]

  before_action :load_autocomplete_data, only: [:new, :edit, :create, :update]
  before_action :load_property_setting, only: [:new, :edit, :create, :update]
  helper_method :can_view_proprietor_data?, :can_view_internal_documents?, :can_manage_internal_documents?,
                :can_view_habitation_show_sensitive_data?, :can_edit_habitation?, :sort_options
  helper_method :can_release_intake_to_broker?, :can_manage_intake_status?, :can_complete_admin_intake_review?
  helper_method :can_filter_by_broker?, :can_filter_by_proprietor?, :can_export_proprietor_data?
  helper_method :can_view_habitation_administrative_filters?
  helper_method :can_view_habitation_owner_contact_data?
  helper_method :can_create_internal_intake?
  helper_method :can_destroy_habitation?
  helper_method :can_duplicate_habitation?
  helper_method :can_bulk_publish_habitations?
  helper_method :can_edit_protected_habitation_fields?
  helper_method :can_manage_habitation_responsibles?
  helper_method :broker_restricted_habitation_edit?, :broker_habitation_allowed_fields,
                :broker_habitation_allowed_actions
  helper_method :active_extra_filters_count, :clear_extra_filter_params
  helper_method :owns_all_resource?

  def index
    if clear_habitations_filter_session_requested?
      clear_habitations_filter_session!
      redirect_to admin_habitations_path(ownership: params[:ownership].presence_in(%w[mine all]) || "all"), status: :see_other
      return
    end

    if should_restore_habitations_filter_session?
      redirect_to admin_habitations_path(habitations_filter_session_params), status: :see_other
      return
    end

    if should_redirect_to_effective_habitations_filter_params?
      redirect_to admin_habitations_path(effective_habitations_filter_params), status: :see_other
      return
    end

    store_habitations_filter_session!
    load_index_filters
    @return_to_path = safe_admin_habitations_return_path(request.fullpath)
    @sort_column = sort_column
    @sort_direction = sort_direction
    @per_page = index_per_page
    @page_size_options = INDEX_PAGE_SIZE_OPTIONS
    filtered_scope = filtered_habitations_scope
    load_pwa_habitation_nav_counts
    order_clauses = []
    search_relevance_order = habitation_search_relevance_order_sql(@q)
    order_clauses << Arel.sql("#{search_relevance_order} ASC") if search_relevance_order.present?
    order_clauses << Arel.sql("#{sort_expression} #{@sort_direction} NULLS LAST")

    @habitations = filtered_scope
      .includes(:address, :admin_user, :proprietor, { empreendimento: { photos_attachments: :blob } }, { broker_assignments: :admin_user }, { photos_attachments: :blob })
      .order(*order_clauses)

    @habitations = @habitations.paginate(page: params[:page], per_page: @per_page)
    @filtered_count = @habitations.total_entries
    @page_title = "Gerenciar Imóveis"
    @report_types = REPORT_TYPES
    @export_fields = EXPORT_FIELDS
    @default_export_fields = %w[codigo categoria logradouro numero complemento dormitorios_qtd valor_venda valor_locacao]
    @recent_exports = current_admin_user.habitation_exports.recent.limit(5)
    record_catalog_user_activity
  end

  def filter_inspector
    unless turbo_frame_request?
      redirect_to admin_habitations_path(request.query_parameters.except("controller", "action")), status: :see_other
      return
    end

    expires_now
    load_index_filters
    load_filter_data

    render :filter_inspector, layout: false
  end

  def proprietor_options
    return head :forbidden unless can_filter_by_proprietor?

    query = params[:q].to_s.strip
    selected_ids = Array(params[:ids]).flat_map { |value| value.to_s.split(",") }.filter_map do |value|
      Integer(value, exception: false)
    end.uniq

    scope = current_tenant.proprietors.select(:id, :name, :phone_primary, :mobile_phone, :residential_phone, :business_phone, :email)

    proprietors =
      if query.present?
        term = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
        text_matches = scope.where(
          "proprietors.name ILIKE :term OR proprietors.phone_primary ILIKE :term OR proprietors.mobile_phone ILIKE :term OR proprietors.email ILIKE :term",
          term:
        )
        # CPF cifrado: casa por documento completo digitado (com ou sem máscara)
        digits = Proprietor.normalized_cpf_cnpj(query)
        matches =
          if Proprietor.cpf_digits_searchable? && digits.length >= 11
            text_matches.or(scope.where(cpf_cnpj_digits: digits))
          elsif Proprietor.cpf_digits_searchable?
            text_matches
          else
            scope.where(
              "proprietors.name ILIKE :term OR proprietors.phone_primary ILIKE :term OR proprietors.mobile_phone ILIKE :term OR proprietors.cpf_cnpj ILIKE :term OR proprietors.email ILIKE :term",
              term:
            )
          end
        matches.order(:name).limit(20)
      elsif selected_ids.any?
        scope.where(id: selected_ids).order(:name).limit(20)
      else
        current_tenant.proprietors.none
      end

    render json: proprietors.map { |proprietor| { value: proprietor.id, text: proprietor.select_label } }
  end

  def search_by_code
    code = params[:codigo].to_s.strip
    if code.blank?
      redirect_back fallback_location: admin_habitations_path, alert: "Informe o código do imóvel ou empreendimento."
      return
    end

    habitation =
      current_tenant.habitations.find_by(codigo: code) ||
      current_tenant.habitations.find_by(codigo_dwv: code) ||
      resolve_admin_habitation_param(code)
    unless habitation
      redirect_back fallback_location: admin_habitations_path, alert: "Nenhum cadastro encontrado para o código #{code}."
      return
    end

    catalog_code = [habitation.codigo, habitation.codigo_dwv].map(&:to_s).include?(code) ? code : habitation.codigo
    code_filter_params = {
      "ownership" => params[:ownership].presence_in(%w[mine all]) || "all",
      "codigo" => catalog_code
    }
    session[habitations_filter_session_key] = compact_habitations_filter_session_payload(
      compact_blank_return_params(code_filter_params)
    )

    return_to_path = admin_habitations_path(code_filter_params)
    path = can_edit_habitation?(habitation) ? edit_admin_habitation_path(habitation.id) : admin_habitation_path(habitation.id)
    redirect_to admin_path_with_flat_return(path, return_to_path)
  end

  def print
    load_index_filters
    @sort_column = sort_column
    @sort_direction = sort_direction
    @report_type = normalized_report_type
    @report_title = REPORT_TYPES[@report_type]
    @report_generated_at = Time.current
    @full_print_mode = full_print_mode?
    @public_site_profile = PublicSiteProfile.current(tenant: current_tenant)

    scope = filtered_habitations_scope.order(Arel.sql("#{sort_expression} #{@sort_direction} NULLS LAST"))
    ids = single_habitation_sheet_report? ? [] : sanitized_selected_ids
    scope = scope.where(id: ids) if ids.any?

    case @report_type
    when "client_sheet_commercial"
      scope = scope.where(categoria: Habitation::REGISTRATION_PROFILES.dig("comerciais_industriais", :categories))
    when "client_sheet_residential"
      excluded_categories =
        Habitation::REGISTRATION_PROFILES.dig("comerciais_industriais", :categories) +
        Habitation::REGISTRATION_PROFILES.dig("terrenos", :categories)
      scope = scope.where.not(categoria: excluded_categories)
    when "client_sheet_land"
      scope = scope.where(categoria: Habitation::REGISTRATION_PROFILES.dig("terrenos", :categories))
    end

    if single_habitation_sheet_report?
      setup_single_habitation_sheet_report(scope)
    elsif @report_type == "property_count_by_broker"
      @broker_rows = scope.reorder(nil)
        .group("COALESCE(NULLIF(TRIM(corretor_nome), ''), 'Sem corretor')")
        .order(Arel.sql("COUNT(*) DESC"))
        .count
    elsif @report_type == "sale_rent_total_values"
      grouped_rows = scope.to_a.group_by { |h| h.categoria.to_s.strip.presence || "Sem categoria" }
      @summary_rows = grouped_rows.map do |category, rows|
        sale_total = rows.sum { |h| h.valor_venda_cents.to_i } / 100.0
        rent_total = rows.sum { |h| h.valor_locacao_cents.to_i } / 100.0
        {
          category: category,
          total_units: rows.size,
          sale_total: sale_total,
          rent_total: rent_total
        }
      end.sort_by { |row| row[:category].to_s.downcase }
      @summary_totals = {
        units: @summary_rows.sum { |row| row[:total_units] },
        sale_total: @summary_rows.sum { |row| row[:sale_total] },
        rent_total: @summary_rows.sum { |row| row[:rent_total] }
      }
    else
      if @full_print_mode
        setup_full_report(scope)
      else
        setup_paginated_report(scope)
      end
    end

    record_data_export!(
      export_type: "print_report",
      format: "html_print",
      record_count: data_export_count_for(scope),
      selected_count: ids.size,
      fields: [@report_type],
      filters: data_export_filters,
      metadata: { report_type: @report_type, full_print: @full_print_mode }
    )

    render layout: false
  end

  # Enfileira a geração assíncrona do CSV e retorna o registro (JSON) para o modal acompanhar.
  def export
    load_index_filters
    @sort_column = sort_column
    @sort_direction = sort_direction
    fields = sanitized_export_fields

    scope = filtered_habitations_scope.order(Arel.sql("#{sort_expression} #{@sort_direction} NULLS LAST"))
    ids = sanitized_selected_ids
    scope = scope.where(id: ids) if ids.any?

    source_ids = scope.pluck(:id)
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    filename = "imoveis_exportacao_#{timestamp}.csv"

    export = current_admin_user.habitation_exports.create!(
      status: "pending", progress: 0, filename: filename,
      fields: fields, source_ids: source_ids, col_sep: export_col_sep,
      record_count: source_ids.size
    )

    record_data_export!(
      export_type: "csv_export",
      format: params[:data_format].to_s.presence || "csv",
      record_count: source_ids.size,
      selected_count: ids.size,
      fields: fields,
      filename: filename,
      filters: data_export_filters,
      metadata: { sort_column: @sort_column, sort_direction: @sort_direction, async: true }
    )

    Admin::HabitationExportJob.perform_later(export.id)
    prune_old_exports!

    respond_to do |format|
      format.json { render json: export_json(export) }                                   # caminho JS (fetch)
      format.any  { redirect_to admin_habitations_path, notice: "Exportação iniciada — acompanhe em “Exportar”." } # fallback sem JS
    end
  end

  # Últimas exportações do usuário (para listar no modal).
  def exports
    render json: { exports: current_admin_user.habitation_exports.recent.limit(5).map { |e| export_json(e) } }
  end

  # Status de uma exportação (polling do progresso).
  def export_status
    export = current_admin_user.habitation_exports.find_by(id: params[:export_id])
    return head :not_found unless export

    render json: export_json(export)
  end

  def download_export
    export = current_admin_user.habitation_exports.find_by(id: params[:export_id])
    return head :not_found unless export&.ready?

    send_data export.file.download, filename: export.filename, type: "text/csv; charset=utf-8", disposition: "attachment"
  end

  def destroy_export
    export = current_admin_user.habitation_exports.find_by(id: params[:export_id])
    if export
      export.file.purge_later if export.file.attached?
      export.destroy
    end
    respond_to do |format|
      format.json { head :no_content }                          # caminho JS (fetch)
      format.any  { redirect_to admin_habitations_path }         # fallback sem JS (button_to)
    end
  end

  BULK_PUBLISH_CHANNELS = {
    "site"             => { flag: :exibir_no_site_flag, options: [] },
    "lais_ai"          => { flag: :publicar_lais_ai, options: [] },
    "chaves_na_mao"    => { flag: :publicar_chaves_na_mao, options: [:destaque_chaves_na_mao, :periodo_locacao_chaves_na_mao] },
    "casa_mineira"     => { flag: :publicar_casa_mineira, options: [:modelo_casa_mineira] },
    "imovelweb"        => { flag: :publicar_imovelweb, options: [:tipo_publicacao_imovelweb, :mostrar_mapa_imovelweb] },
    "imovelweb_2"      => { flag: :publicar_imovelweb_2, options: [:tipo_publicacao_imovelweb_2, :mostrar_mapa_imovelweb_2] },
    "viva_real_vrsync" => { flag: :publicar_viva_real_vrsync, options: [:tipo_publicacao_viva_real, :divulgar_endereco_viva_real] }
  }.freeze

  def bulk_publish
    ids = resolve_bulk_ids
    action_type = params[:action_type].to_s
    channels = Array(params[:channels]).map(&:to_s) & BULK_PUBLISH_CHANNELS.keys

    if ids.empty?
      return render json: { error: "Nenhum imóvel selecionado." }, status: :unprocessable_entity
    end
    unless %w[publicar despublicar].include?(action_type)
      return render json: { error: "Ação inválida." }, status: :unprocessable_entity
    end
    if channels.empty?
      return render json: { error: "Selecione ao menos um canal." }, status: :unprocessable_entity
    end

    updates = {}
    flag_value = (action_type == "publicar")
    site_flag_touched = false
    portals_touched = []

    channels.each do |channel_key|
      config = BULK_PUBLISH_CHANNELS[channel_key]
      updates[config[:flag]] = flag_value
      site_flag_touched = true if config[:flag] == :exibir_no_site_flag
      portals_touched << channel_key unless channel_key == "site"

      if flag_value
        config[:options].each do |option_key|
          value = params.dig(:channel_options, channel_key, option_key).presence
          updates[option_key] = value if value
        end
      end
    end

    target_ids = ids
    if flag_value
      target_ids = current_tenant.habitations.where(id: ids).commercially_publishable.reorder(nil).pluck(:id)
      if target_ids.empty?
        return render json: { error: "Nenhum imóvel selecionado pode ser publicado com o status comercial atual." }, status: :unprocessable_entity
      end
    end

    # Bump updated_at so feed ETags e cache_keys das habitations invalidem automaticamente
    updates[:updated_at] = Time.current
    bulk_audit_changesets = bulk_habitation_audit_changesets(target_ids, updates)

    updated_count = 0
    Habitation.transaction do
      updated_count = current_tenant.habitations.where(id: target_ids).update_all(updates)
      record_bulk_habitation_updates(bulk_audit_changesets, action_type: action_type, channels: channels)
    end

    # Invalida caches individuais (replica o after_save :clear_cache manualmente, pois update_all pula callbacks)
    target_ids.each do |habitation_id|
      Rails.cache.delete("habitation_#{habitation_id}")
      Rails.cache.delete([Habitation.name, habitation_id])
    end

    # Materialized view de destaques depende de exibir_no_site_flag
    if site_flag_touched && defined?(RefreshFeaturedPropertiesJob)
      RefreshFeaturedPropertiesJob.perform_later
    end

    # Bump last_feed_at nas integrations afetadas pra sinalizar no admin que houve mudança
    if portals_touched.any?
      portal_keys = Habitation::PORTAL_PUBLICATION_FIELDS.select { |_, col| updates.key?(col) }.keys
      current_tenant.portal_integrations.where(portal: portal_keys).update_all(updated_at: Time.current) if portal_keys.any?
    end

    render json: {
      updated: updated_count,
      skipped_inactive_status: ids.size - target_ids.size,
      action_type: action_type,
      channels: channels
    }
  end

  def bulk_publish_eligibility
    ids = resolve_bulk_ids
    channel = params[:channel].to_s
    action_type = params[:action_type].to_s
    config = BULK_PUBLISH_CHANNELS[channel]

    unless config && %w[publicar despublicar].include?(action_type)
      return render json: { error: "Parâmetros inválidos." }, status: :unprocessable_entity
    end

    flag_column = config[:flag]
    target_flag = (action_type == "despublicar")
    eligible_scope = current_tenant.habitations.where(id: ids).where(flag_column => target_flag)
    eligible_scope = eligible_scope.commercially_publishable if action_type == "publicar"
    eligible = eligible_scope.count

    render json: { total: ids.size, eligible: eligible }
  end

  def share_selection
    setting = PropertySetting.instance(tenant: current_tenant)
    return render json: { error: setting.ai_property_search_sharing_disabled_message }, status: :forbidden unless setting.ai_property_search_sharing_enabled?

    ids = resolve_bulk_ids
    if ids.empty?
      return render json: { error: "Selecione ao menos dois imóveis para compartilhar." }, status: :unprocessable_entity
    end

    result = Ai::PropertyShareCollectionCreator.call(
      tenant: current_tenant,
      admin_user: current_admin_user,
      setting:,
      scope: current_tenant.habitations.where(id: ids),
      source: "admin_catalog_selection",
      min_count: 2
    )
    record_user_activity!(
      "selection_shared",
      result_count: result.habitations.size,
      visible_habitation_ids: result.habitations.map(&:id),
      metadata: { source: "admin_catalog_selection", requested_count: ids.size }
    )

    render json: {
      url: ai_property_share_collection_url(result.collection.token),
      count: result.habitations.size,
      message: "Link da seleção copiado. Agora você pode compartilhar."
    }
  rescue Ai::PropertyShareCollectionCreator::TooFewShareableRecords
    render json: { error: "Selecione ao menos dois imóveis com status Venda ou Aluguel." }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Nenhum imóvel selecionado pode ser compartilhado." }, status: :unprocessable_entity
  end

  def new
    @habitation = current_tenant.habitations.new
    @registration_profiles = Habitation::REGISTRATION_PROFILES
    assign_new_habitation_defaults(@habitation)
    prepare_development_from_source(@habitation)
    prepare_admin_paper_intake(@habitation) if admin_paper_intake_form?
    @habitation.build_address
    @page_title = admin_paper_intake_form? ? "Nova ficha interna de captação" : "Novo Imóvel"
    @return_to_path = safe_admin_habitations_return_path(params[:return_to])
    @show_registration_profile_start = !admin_paper_intake_form? && !source_habitation.present? && !admin_habitation_profile_started?
  end

  def show
    @page_title = "Detalhes do Imóvel: #{@habitation.codigo}"
    @return_to_path = safe_admin_habitations_return_path(params[:return_to])
    record_user_activity!(
      "property_opened",
      habitation: @habitation,
      metadata: {
        codigo: @habitation.codigo,
        status: @habitation.status,
        category: @habitation.categoria,
        source: "admin_habitation_show"
      }
    )
  end

  def gallery
    items = @habitation.public_image_sources.each_with_index.filter_map do |source, index|
      url = Storage::PublicCdnImageUrl.resolve(source)
      next if url.blank?

      {
        src: url,
        thumb_src: url,
        type: "image",
        caption: "#{@habitation.display_title} - Foto #{index + 1}"
      }
    end

    render json: { items: }
  end

  def confirm_owner_contact
    unless ActiveModel::Type::Boolean.new.cast(params[:owner_contact_confirmed])
      redirect_to edit_admin_habitation_path(@habitation),
                  alert: "Confirme que falou com o proprietário e não houve alteração."
      return
    end

    confirmed_at = Time.current
    @habitation.skip_auto_audit = true
    @habitation.update!(data_atualizacao_crm: confirmed_at)
    record_owner_contact_confirmed(@habitation, confirmed_at:)

    redirect_to edit_admin_habitation_path(@habitation),
                notice: "Atualização registrada no histórico do imóvel."
  end

  def create
    source_habitation
    permitted_attributes = habitation_params
    new_photo_uploads = extract_photo_uploads!(permitted_attributes)
    new_document_uploads = extract_document_uploads!(permitted_attributes)
    @habitation = current_tenant.habitations.new(permitted_attributes)
    @habitation.skip_auto_audit = true
    prepare_admin_paper_intake(@habitation) if admin_paper_intake_form?
    apply_picture_removals_to_memory(@habitation)
    releasing_to_broker = release_intake_to_broker_requested?
    saving_internal_intake = save_internal_intake_requested?

    if releasing_to_broker || saving_internal_intake
      unless can_complete_admin_intake_review?(@habitation)
        load_autocomplete_data
        @habitation.errors.add(:base, "Você não tem permissão para concluir esta revisão.")
        render :new, status: :unprocessable_entity
        return
      end

      required_checks = review_required_checks_for(@habitation)
      unless @habitation.intake_ready_for_admin_review?(required_checks: required_checks, require_owner_city: true)
        @habitation.intake_missing_requirements(required_checks: required_checks, require_owner_city: true).each { |message| @habitation.errors.add(:base, message) }
        load_autocomplete_data
        render :new, status: :unprocessable_entity
        return
      end

      if releasing_to_broker
        mark_intake_as_admin_approved(@habitation)
      else
        mark_intake_as_internal(@habitation)
      end
      snapshot_review_policy!(@habitation)
    end

    assign_proprietor_from_legacy_fields(@habitation) if can_sync_habitation_proprietor?
    apply_intake_status_transition_metadata(@habitation)

    unless no_duplicate_address?(@habitation)
      load_autocomplete_data
      render :new, status: :unprocessable_entity
      return
    end

    if @habitation.save
      link_source_habitation_to_development!(@habitation)
      attach_new_photos(@habitation, new_photo_uploads, apply_watermark: apply_photo_watermark_requested?)
      attach_new_documents(@habitation, new_document_uploads)
      record_habitation_created(@habitation)
      apply_saved_photo_removals(@habitation)
      notice = if releasing_to_broker
                 "Imóvel salvo e enviado ao captador para publicar no site."
               elsif saving_internal_intake
                 "Imóvel salvo internamente e disponibilizado no catálogo."
               else
                 "Imóvel criado com sucesso."
               end
      redirect_after_habitation_save(@habitation, notice: notice)
    else
      load_autocomplete_data
      render :new, status: :unprocessable_entity
    end
  end

  def duplicate
    unless can_duplicate_habitation?(@habitation)
      redirect_to admin_habitations_path, alert: "Você não tem permissão para duplicar este imóvel."
      return
    end

    result = Habitations::Duplicator.new(
      @habitation,
      actor: current_admin_user,
      tenant: current_tenant,
      request: request,
      copy_sensitive_data: can_view_proprietor_data?(@habitation),
      copy_internal_documents: can_manage_internal_documents?
    ).call!

    redirect_to edit_admin_habitation_path(result.habitation),
                notice: "Imóvel duplicado com o novo código #{result.habitation.codigo}. Revise antes de publicar no site ou portais."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_admin_habitation_path(@habitation),
                alert: "Não foi possível duplicar o imóvel: #{e.record.errors.full_messages.to_sentence.presence || e.message}."
  end


  def edit
    @page_title = "Editar Imóvel: #{@habitation.codigo}"
    @return_to_path = safe_admin_habitations_return_path(params[:return_to])
    preload_habitation_form_associations
    load_ai_suggestion
  end

  def operational_hub
    tab = params[:tab].presence_in(%w[overview changes publication intake]) || "overview"

    case tab
    when "overview"
      preload_operational_hub_associations
      summary = Habitations::OperationalSummary.new(@habitation)
      render partial: "admin/habitations/operational_overview", locals: { habitation: @habitation, summary: summary }
    when "publication"
      preload_operational_hub_associations
      logs = operational_hub_logs.select { |log| (log.changed_fields & HabitationAuditLog.publication_fields).any? }
      summary = Habitations::OperationalSummary.new(@habitation)
      render partial: "admin/habitations/operational_publication", locals: { habitation: @habitation, summary: summary, logs: logs }
    when "intake"
      logs = operational_hub_logs.select { |log| (log.changed_fields & HabitationAuditLog.intake_fields).any? }
      render partial: "admin/habitations/operational_intake",
             locals: {
               habitation: @habitation,
               logs: logs,
               can_view_owner_contact_data: can_view_habitation_owner_contact_data?(@habitation)
             }
    else
      logs = operational_hub_logs
      render partial: "admin/habitations/audit_history_timeline", locals: { tab_id: "hub-#{tab}", active: true, logs: logs }
    end
  end

  # Pré-carrega as associações que o form de responsáveis acessa por item
  # (habitation.admin_user + broker_assignments.admin_user) — sem isso o render
  # dispara N+1 em admin_users. Best-effort: nunca derruba a edição.
  def preload_habitation_form_associations
    ActiveRecord::Associations::Preloader.new(
      records: [@habitation],
      associations: [:admin_user, { broker_assignments: :admin_user }]
    ).call
  rescue StandardError => e
    Rails.logger.warn("[habitations#edit] preload de associações falhou: #{e.message}")
  end

  def update
    audit_snapshot_before = Habitations::AuditChangeRecorder.snapshot_for(@habitation)
    @habitation.skip_auto_audit = true
    permitted_attributes = habitation_params
    new_photo_uploads = extract_photo_uploads!(permitted_attributes)
    new_document_uploads = extract_document_uploads!(permitted_attributes)
    @habitation.assign_attributes(permitted_attributes)
    touch_manual_habitation_update!(@habitation, force: new_photo_uploads.present? || new_document_uploads.present?)
    apply_picture_removals_to_memory(@habitation)
    keep_admin_review_intake_hidden

    unless no_duplicate_address?(@habitation)
      prepare_habitation_address
      load_ai_suggestion
      render :edit, status: :unprocessable_entity
      return
    end

    releasing_to_broker = release_intake_to_broker_requested?
    saving_internal_intake = save_internal_intake_requested?
    if releasing_to_broker || saving_internal_intake
      unless can_release_intake_to_broker?(@habitation)
        redirect_to edit_admin_habitation_path(@habitation.id), alert: "Você não tem permissão para concluir esta revisão."
        return
      end

      if new_document_uploads.present?
        attach_new_documents(@habitation, new_document_uploads)
        new_document_uploads = {}
      end

      required_checks = review_required_checks_for(@habitation)
      unless @habitation.intake_ready_for_admin_review?(required_checks: required_checks, require_owner_city: true)
        @habitation.intake_missing_requirements(required_checks: required_checks, require_owner_city: true).each { |message| @habitation.errors.add(:base, message) }
        prepare_habitation_address
        load_ai_suggestion
        render :edit, status: :unprocessable_entity
        return
      end

      if releasing_to_broker
        mark_intake_as_admin_approved(@habitation)
      else
        mark_intake_as_internal(@habitation)
      end
      snapshot_review_policy!(@habitation)
    end

    assign_proprietor_from_legacy_fields(@habitation) if can_sync_habitation_proprietor?
    apply_intake_status_transition_metadata(@habitation)
    rental_short_cycle_alert = rental_short_cycle_alert_payload(@habitation, before_snapshot: audit_snapshot_before)
    if @habitation.save
      attach_new_photos(@habitation, new_photo_uploads, apply_watermark: apply_photo_watermark_requested?)
      attach_new_documents(@habitation, new_document_uploads)
      record_habitation_updated(@habitation, before_snapshot: audit_snapshot_before)
      record_rental_short_cycle_alert(@habitation, rental_short_cycle_alert) if rental_short_cycle_alert.present?
      apply_saved_photo_removals(@habitation)
      notice = if releasing_to_broker
                 "Imóvel salvo e enviado ao captador para publicar no site."
               elsif saving_internal_intake
                 "Imóvel salvo internamente e disponibilizado no catálogo."
               else
                 "Imóvel atualizado com sucesso."
               end
      if rental_short_cycle_alert.present?
        notice = "#{notice} Alerta registrado: locação encerrada em menos de 30 dias."
      end
      redirect_after_habitation_save(@habitation, notice: notice)
    else
      prepare_habitation_address
      load_ai_suggestion
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    unless can_destroy_habitation?
      redirect_to admin_habitations_path, alert: "Você não tem permissão para excluir imóveis."
      return
    end

    Habitation.transaction do
      @habitation.skip_auto_audit = true
      record_habitation_destroyed(@habitation)
      release_habitation_destroy_references(@habitation)
      @habitation.destroy!
    end

    redirect_to admin_habitations_path, notice: "Imóvel excluído com sucesso."
  rescue ActiveRecord::InvalidForeignKey => error
    Rails.logger.error("[habitation_destroy] failed id=#{@habitation&.id} error=#{error.class}: #{error.message}")
    redirect_to edit_admin_habitation_path(@habitation), alert: "Não foi possível excluir o imóvel porque ainda existem vínculos internos. O erro foi registrado para correção."
  end

  def generate_ai_preview
    unless Ai::PropertyContentService.connected?(tenant: @habitation.tenant)
      if turbo_frame_request?
        return render_ai_content_preview(message: "Configure o token da OpenAI em Integrações > IA antes de gerar a sugestão.", message_type: "warning")
      end

      return redirect_to edit_admin_habitation_path(@habitation.id, anchor: "features"), alert: "Configure o token da OpenAI em Integrações > IA antes de gerar a sugestão."
    end

    suggestion = Ai::PropertyContentService.new(@habitation, admin_user: current_admin_user).generate_suggestion!
    return render_ai_content_preview(suggestion: suggestion, message: "Sugestão gerada e carregada nos campos para revisão.", message_type: "success") if turbo_frame_request?

    redirect_to edit_admin_habitation_path(@habitation.id, anchor: "features"), notice: "Sugestão com IA gerada para revisão."
  rescue => e
    return render_ai_content_preview(message: "Erro ao gerar sugestão com IA: #{e.message}", message_type: "danger") if turbo_frame_request?

    redirect_to edit_admin_habitation_path(@habitation.id, anchor: "features"), alert: "Erro ao gerar sugestão com IA: #{e.message}"
  end

  def format_ai_suggestion
    suggestion = @habitation.ai_property_suggestions.pending.find(params[:suggestion_id])
    suggestion.update!(
      generated_title: suggestion.generated_title.to_s.squish,
      generated_description: Ai::PropertyTextFormatter.call(suggestion.generated_description)
    )

    return render_ai_content_preview(suggestion: suggestion, message: "Texto formatado para revisão.", message_type: "success") if turbo_frame_request?

    redirect_to edit_admin_habitation_path(@habitation.id, anchor: "features"), notice: "Texto formatado para revisão."
  rescue ActiveRecord::RecordNotFound
    return render_ai_content_preview(message: "Sugestão não encontrada ou já aplicada.", message_type: "warning") if turbo_frame_request?

    redirect_to edit_admin_habitation_path(@habitation.id, anchor: "features"), alert: "Sugestão não encontrada ou já aplicada."
  rescue => e
    return render_ai_content_preview(message: "Erro ao formatar texto: #{e.message}", message_type: "danger") if turbo_frame_request?

    redirect_to edit_admin_habitation_path(@habitation.id, anchor: "features"), alert: "Erro ao formatar texto: #{e.message}"
  end

  def apply_ai_suggestion
    suggestion = @habitation.ai_property_suggestions.pending.find(params[:suggestion_id])
    Ai::PropertyContentService.new(@habitation, admin_user: current_admin_user).apply!(suggestion)

    return render_ai_content_preview(suggestion: nil, message: "Sugestão aplicada ao título, descrição e SEO do imóvel.", message_type: "success") if turbo_frame_request?

    redirect_to edit_admin_habitation_path(@habitation.id, anchor: "features"), notice: "Sugestão aplicada ao título, descrição e SEO do imóvel."
  rescue ActiveRecord::RecordNotFound
    return render_ai_content_preview(message: "Sugestão não encontrada ou já aplicada.", message_type: "warning") if turbo_frame_request?

    redirect_to edit_admin_habitation_path(@habitation.id, anchor: "features"), alert: "Sugestão não encontrada ou já aplicada."
  rescue => e
    return render_ai_content_preview(message: "Erro ao aplicar sugestão: #{e.message}", message_type: "danger") if turbo_frame_request?

    redirect_to edit_admin_habitation_path(@habitation.id, anchor: "features"), alert: "Erro ao aplicar sugestão: #{e.message}"
  end

  # Remove um anexo individual (ficha de cadastro ou autorização) do imóvel.
  # Restrito aos imóveis do habitation; valida o nome da associação por allowlist.
  def purge_attachment
    @habitation = find_admin_habitation_param!(params[:id])
    association = params[:association].to_s
    allowed = %w[fichas_cadastro autorizacoes_venda photos]
    unless allowed.include?(association)
      redirect_to edit_habitation_path_with_return(@habitation, anchor: "documents"), alert: "Anexo inválido."
      return
    end
    if association.in?(%w[fichas_cadastro autorizacoes_venda]) && !can_manage_internal_documents?
      redirect_to edit_habitation_path_with_return(@habitation, anchor: "documents"), alert: "Você não tem permissão para remover documentos internos."
      return
    end
    if association.in?(%w[fichas_cadastro autorizacoes_venda])
      action_key = "acao:remover_#{association}"
      if Habitations::FieldLockPolicy.for(current_admin_user).action_locked?(action_key)
        redirect_to edit_habitation_path_with_return(@habitation, anchor: "documents"), alert: "Este perfil não pode remover esse tipo de documento."
        return
      end
    end

    attachment = @habitation.public_send(association).attachments.find_by(id: params[:attachment_id])
    if attachment.nil?
      redirect_to edit_habitation_path_with_return(@habitation, anchor: "documents"), alert: "Anexo não encontrado."
      return
    end

    attachment_payload = Habitations::AuditChangeRecorder.attachment_payload(attachment)
    record_habitation_attachment_removed(@habitation, association: association, attachment_payload: attachment_payload)
    Storage::BlobAuditRecorder.record!(
      blob: attachment.blob,
      action: "purge_requested",
      source: "admin_habitation_purge_attachment",
      attachment: attachment,
      metadata: {
        habitation_id: @habitation.id,
        association: association
      }
    )
    attachment.purge_later
    anchor = association == "photos" ? "media" : "documents"
    notice = association == "photos" ? "Foto removida." : "Anexo removido."
    redirect_to edit_habitation_path_with_return(@habitation, anchor: anchor), notice: notice
  end

  private

  def scope_habitations_by_permission
    return if owns_all_resource?(:imoveis)
    identifier = params[:id] || params[:habitation_id]
    return if identifier.blank?
    habitation = resolve_admin_habitation_param(identifier)
    unless habitation && property_accessible?(habitation)
      redirect_to admin_habitations_path, alert: "Você não tem acesso a este imóvel."
    end
  end

  def authorize_data_export!
    return if tenant_owner? || owns_all_resource?(:imoveis)

    redirect_to admin_habitations_path, alert: "Você não tem permissão para imprimir ou exportar imóveis."
  end

  def authorize_habitation_edit!
    unless can_edit_habitation?(@habitation)
      redirect_to admin_habitations_path, alert: "Você não tem permissão para editar este imóvel."
      return
    end

    return unless @habitation&.broker_intake?
    return unless @habitation.intake_submitted_for_admin_review?
    return if can_complete_admin_intake_review?(@habitation)
    return if current_admin_user&.can_view_team?(:captacoes) && manager_can_view_proprietor_data?(@habitation)

    redirect_to admin_habitations_path, alert: "Captações pendentes de revisão só podem ser alteradas por quem revisa captações ou pelo gestor responsável."
  end

  def authorize_bulk_publish!
    return if can_bulk_publish_habitations?

    render json: { error: "Você não tem permissão para publicação em massa de imóveis." }, status: :forbidden
  end

  # Card #1: geração/aplicação de conteúdo por IA escreve título, descrição e SEO
  # do imóvel — campos bloqueados para o corretor. Restrito a quem edita os
  # campos protegidos (dono do tenant ou imoveis escopo "all").
  def authorize_habitation_ai_content!
    return unless Habitations::FieldLockPolicy.for(current_admin_user).action_locked?("acao:gerar_ia")

    message = "Geração de conteúdo com IA é restrita ao administrador."
    if turbo_frame_request?
      render_ai_content_preview(message: message, message_type: "warning")
    else
      redirect_to edit_admin_habitation_path(@habitation.id, anchor: "features"), alert: message
    end
  end

  def sort_column
    sort_options.fetch(params[:sort].presence, sort_options["codigo"])[:column]
  end

  def sort_expression
    column = sort_column.to_s
    column.include?("(") ? column : "habitations.#{column}"
  end

  def sort_direction
    return params[:direction] if %w[asc desc].include?(params[:direction])

    sort_options.fetch(params[:sort].presence, sort_options["codigo"])[:default_direction]
  end
  helper_method :sort_column, :sort_direction

  def habitation_search_relevance_order_sql(query)
    sanitized = query.to_s.squish
    return if sanitized.blank?

    exact = ActiveRecord::Base.connection.quote(sanitized)
    prefix = ActiveRecord::Base.connection.quote("#{ActiveRecord::Base.sanitize_sql_like(sanitized)}%")
    phrase = ActiveRecord::Base.connection.quote("%#{ActiveRecord::Base.sanitize_sql_like(sanitized)}%")
    linked_development_exact_match = <<~SQL.squish
      EXISTS (
        SELECT 1
        FROM habitations developments
        WHERE developments.codigo = habitations.codigo_empreendimento
          AND developments.tenant_id = habitations.tenant_id
          AND LOWER(unaccent(COALESCE(developments.nome_empreendimento, ''))) = LOWER(unaccent(#{exact}))
      )
    SQL
    linked_development_prefix_match = <<~SQL.squish
      EXISTS (
        SELECT 1
        FROM habitations developments
        WHERE developments.codigo = habitations.codigo_empreendimento
          AND developments.tenant_id = habitations.tenant_id
          AND unaccent(COALESCE(developments.nome_empreendimento, '')) ILIKE unaccent(#{prefix})
      )
    SQL
    linked_development_phrase_match = <<~SQL.squish
      EXISTS (
        SELECT 1
        FROM habitations developments
        WHERE developments.codigo = habitations.codigo_empreendimento
          AND developments.tenant_id = habitations.tenant_id
          AND unaccent(COALESCE(developments.nome_empreendimento, '')) ILIKE unaccent(#{phrase})
      )
    SQL

    <<~SQL.squish
      CASE
        WHEN habitations.codigo = #{exact} OR habitations.codigo_dwv = #{exact} THEN 0
        WHEN LOWER(unaccent(COALESCE(habitations.nome_empreendimento, ''))) = LOWER(unaccent(#{exact})) THEN 1
        WHEN #{linked_development_exact_match} THEN 1
        WHEN unaccent(COALESCE(habitations.nome_empreendimento, '')) ILIKE unaccent(#{prefix}) THEN 2
        WHEN #{linked_development_prefix_match} THEN 2
        WHEN unaccent(COALESCE(habitations.nome_empreendimento, '')) ILIKE unaccent(#{phrase}) THEN 3
        WHEN #{linked_development_phrase_match} THEN 3
        WHEN unaccent(COALESCE(habitations.titulo_anuncio, '')) ILIKE unaccent(#{phrase}) THEN 4
        ELSE 9
      END
    SQL
  end

  def sort_options
    SORT_OPTIONS
  end

  def set_habitation
    @habitation = find_admin_habitation_param!(params[:id])
  end

  def prepare_habitation_address
    @habitation.ensure_address
  end

  def prepare_legacy_habitation_address
    @habitation.ensure_legacy_address
  end

  def find_admin_habitation_param!(identifier)
    resolve_admin_habitation_param(identifier) || raise(ActiveRecord::RecordNotFound)
  end

  def resolve_admin_habitation_param(identifier)
    identifier = identifier.to_s.strip
    return if identifier.blank?

    if identifier.match?(/\A\d+\z/)
      current_tenant.habitations.find_by(id: identifier) || current_tenant.habitations.find_by(codigo: identifier)
    else
      current_tenant.habitations.friendly.find(identifier)
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def load_ai_suggestion
    @ai_property_suggestion = @habitation.ai_property_suggestions.pending.latest_first.first
    @ai_failed_suggestion = @habitation.ai_property_suggestions.where(status: "failed").latest_first.first
  end

  def render_ai_content_preview(suggestion: nil, message: nil, message_type: "info")
    render partial: "ai_content_preview",
           locals: {
             habitation: @habitation,
             suggestion: suggestion || @habitation.ai_property_suggestions.pending.latest_first.first,
             failed_suggestion: @habitation.ai_property_suggestions.where(status: "failed").latest_first.first,
             message: message,
             message_type: message_type,
             show_button: false
           }
  end

  def load_autocomplete_data
    tenant_habitations = current_tenant.habitations

    @proprietors = current_tenant.proprietors
      .select(:id, :name, :phone_primary, :mobile_phone, :residential_phone, :business_phone, :email)
      .order(name: :asc, id: :asc)
    @developments = tenant_habitations.empreendimentos
                              .includes(:address)
                              .select(
                                :id, :slug, :codigo, :nome_empreendimento, :titulo_anuncio,
                                :constructor_id, :proprietor_id, :admin_user_id, :data_entrega,
                                :perfil_construcao, :tipo_endereco, :endereco, :numero,
                                :bairro, :bairro_comercial, :cidade, :uf, :cep
                              )
                              .where("NULLIF(TRIM(nome_empreendimento), '') IS NOT NULL AND nome_empreendimento != '.'")
                              .order(nome_empreendimento: :asc)
    @brokers = habitation_visible_admin_users.select(:id, :name).order(name: :asc)

    cached = Rails.cache.fetch("admin/habitations/form_options/v2/tenant/#{current_tenant.id}", expires_in: 2.minutes) do
      base_address_scope = tenant_habitations.left_outer_joins(:address)
      habitation_address_catalogs = current_tenant.attribute_options.where(context: "habitation")

      {
        categories: (
          Habitation::CATEGORIES +
          tenant_habitations.where("NULLIF(TRIM(categoria), '') IS NOT NULL AND categoria != '.'").distinct.pluck(:categoria) +
          ["Empreendimento"]
        ).compact.uniq.sort,
        status_options: (
          Habitation::STATUS_OPTIONS +
          tenant_habitations.where("NULLIF(TRIM(status), '') IS NOT NULL AND status != '.'").distinct.pluck(:status)
        ).compact.uniq,
        cities: base_address_scope
          .where("NULLIF(TRIM(COALESCE(addresses.cidade, habitations.cidade)), '') IS NOT NULL AND COALESCE(addresses.cidade, habitations.cidade) != '.'")
          .distinct
          .pluck(Arel.sql("COALESCE(addresses.cidade, habitations.cidade)"))
          .concat(habitation_address_catalogs.where(category: "city").pluck(:name))
          .compact_blank
          .uniq
          .sort,
        neighborhoods: base_address_scope
          .where("NULLIF(TRIM(COALESCE(addresses.bairro, habitations.bairro)), '') IS NOT NULL AND COALESCE(addresses.bairro, habitations.bairro) != '.'")
          .distinct
          .pluck(Arel.sql("COALESCE(addresses.bairro, habitations.bairro)"))
          .concat(habitation_address_catalogs.where(category: "neighborhood").pluck(:name))
          .compact_blank
          .uniq
          .sort,
        commercial_neighborhoods: base_address_scope
          .where("NULLIF(TRIM(addresses.bairro_comercial), '') IS NOT NULL AND addresses.bairro_comercial != '.'")
          .distinct
          .pluck(Arel.sql("addresses.bairro_comercial"))
          .concat(habitation_address_catalogs.where(category: "commercial_neighborhood").pluck(:name))
          .compact_blank
          .uniq
          .sort,
        street_types: (
          Habitation::STREET_TYPES +
          habitation_address_catalogs.where(category: "street_type").order(name: :asc).pluck(:name)
        ).compact_blank.uniq.sort,
        badges: current_tenant.attribute_options.where(context: 'habitation', category: 'unique_feature').order(name: :asc).pluck(:name),
        imediacoes_options: current_tenant.attribute_options.where(context: 'habitation', category: 'imediacoes').order(name: :asc).pluck(:name),
        internal_features: current_tenant.attribute_options.where(context: 'habitation', category: 'feature').order(name: :asc).pluck(:name),
        external_features: current_tenant.attribute_options.where(context: 'habitation', category: 'infrastructure').order(name: :asc).pluck(:name)
      }
    end

    @cities = cached[:cities]
    @neighborhoods = cached[:neighborhoods]
    @commercial_neighborhoods = cached[:commercial_neighborhoods]
    @street_types = cached[:street_types]
    @badges = cached[:badges]
    @imediacoes_options = cached[:imediacoes_options]
    @internal_features = cached[:internal_features]
    @external_features = cached[:external_features]
    @categories = cached[:categories]
    @status_options = cached[:status_options]
  end

  def load_filter_data
    tenant_habitations = current_tenant.habitations

    cached = Rails.cache.fetch("admin/habitations/filter_data/v8/tenant/#{current_tenant.id}", expires_in: 2.minutes) do
      city_sql = "COALESCE(NULLIF(TRIM(addresses.cidade), ''), NULLIF(TRIM(habitations.cidade), ''))"
      neighborhood_sql = "COALESCE(NULLIF(TRIM(addresses.bairro), ''), NULLIF(TRIM(habitations.bairro), ''))"
      commercial_neighborhood_sql = "COALESCE(NULLIF(TRIM(addresses.bairro_comercial), ''), NULLIF(TRIM(habitations.bairro_comercial), ''))"
      existing_key_locations = tenant_habitations.where("NULLIF(TRIM(key_location), '') IS NOT NULL")
                                         .distinct
                                         .pluck(:key_location)
                                         .sort

      {
        categories: tenant_habitations.where("NULLIF(TRIM(categoria), '') IS NOT NULL AND categoria != '.'")
                              .distinct.pluck(:categoria).sort,
        cities: tenant_habitations.left_outer_joins(:address)
                          .where("#{city_sql} IS NOT NULL AND #{city_sql} != '.'")
                          .distinct
                          .pluck(Arel.sql(city_sql))
                          .sort,
        bairros: tenant_habitations.left_outer_joins(:address)
                           .where("#{neighborhood_sql} IS NOT NULL AND #{neighborhood_sql} != '.'")
                           .distinct
                           .pluck(Arel.sql(neighborhood_sql))
                           .sort,
        bairros_comerciais: tenant_habitations.left_outer_joins(:address)
                                      .where("#{commercial_neighborhood_sql} IS NOT NULL AND #{commercial_neighborhood_sql} != '.'")
                                      .distinct
                                      .pluck(Arel.sql(commercial_neighborhood_sql))
                                      .reject { |name| excluded_commercial_neighborhood?(name) }
                                      .sort,
        key_locations: (Habitation::KEY_LOCATION_OPTIONS + existing_key_locations).uniq,
        empreendimentos: filter_empreendimento_options,
        amenity_features: normalized_amenity_filter_options(
          current_tenant.attribute_options.where(context: 'habitation', category: 'feature').order(name: :asc).pluck(:name)
        ),
        amenity_infrastructure: normalized_amenity_filter_options(
          current_tenant.attribute_options.where(context: 'habitation', category: 'infrastructure').order(name: :asc).pluck(:name)
        ),
        situacoes: (Habitation::SITUATIONS + tenant_habitations.where("NULLIF(TRIM(situacao), '') IS NOT NULL AND situacao != '.'")
                                                       .distinct
                                                       .pluck(:situacao)).uniq.sort,
        faces: (Habitation::FACES + tenant_habitations.where("NULLIF(TRIM(face), '') IS NOT NULL AND face != '.'")
                                              .distinct
                                              .pluck(:face)).uniq.sort,
        ocupacao_statuses: (Habitation::OCUPACAO_STATUS + tenant_habitations.where("NULLIF(TRIM(ocupacao_status), '') IS NOT NULL AND ocupacao_status != '.'")
                                                                    .distinct
                                                                    .pluck(:ocupacao_status)).uniq.sort,
        estado_conservacoes: (Habitation::ESTADO_CONSERVACAO + tenant_habitations.where("NULLIF(TRIM(estado_conservacao), '') IS NOT NULL AND estado_conservacao != '.'")
                                                                        .distinct
                                                                        .pluck(:estado_conservacao)).uniq.sort
      }
    end

    @filter_categories = cached[:categories]
    @filter_cities = cached[:cities]
    @filter_bairros = cached[:bairros]
    @filter_bairros_comerciais = cached[:bairros_comerciais]
    @filter_statuses = filter_status_options_for(tenant_habitations)
    @filter_key_locations = cached[:key_locations]
    @filter_empreendimentos = cached[:empreendimentos]
    @filter_amenity_feature_options = cached[:amenity_features] || []
    @filter_amenity_infrastructure_options = cached[:amenity_infrastructure] || []
    @filter_amenity_options = (@filter_amenity_feature_options + @filter_amenity_infrastructure_options).uniq
    @filter_brokers = catalog_filter_admin_users.order(name: :asc).pluck(:name, :id)
    @filter_proprietors = selected_filter_proprietors
    @filter_situacoes = cached[:situacoes]
    @filter_faces = cached[:faces]
    @filter_ocupacao_statuses = cached[:ocupacao_statuses]
    @filter_estado_conservacoes = cached[:estado_conservacoes]
    @filter_regioes_foco = Habitation::REGIAO_FOCO_OPTIONS
  end

  def filter_status_options_for(scope)
    return ["Todos"] + sorted_habitation_statuses(permitted_habitation_filter_statuses) if broker_catalog_user?

    statuses = Habitation::STATUS_OPTIONS +
      scope.where("NULLIF(TRIM(status), '') IS NOT NULL AND status != '.'")
           .distinct
           .pluck(:status)

    ["Todos"] + sorted_habitation_statuses(statuses)
  end

  def permitted_habitation_filter_statuses
    broker_catalog_user? ? Habitation::STATUS_OPTIONS : nil
  end

  def sorted_habitation_statuses(statuses)
    Array(statuses).compact_blank.uniq.sort_by { |status| I18n.transliterate(status).downcase }
  end

  def selected_filter_proprietors
    return [] unless can_filter_by_proprietor?

    selected_ids = Array(params[:proprietor_id]).flat_map { |value| value.to_s.split(",") }.filter_map do |value|
      Integer(value, exception: false)
    end.uniq
    return [] if selected_ids.blank?

    Proprietor
      .select(:id, :name, :phone_primary, :mobile_phone, :residential_phone, :business_phone, :email)
      .where(id: selected_ids)
      .order(:name)
      .map { |proprietor| [proprietor.select_label, proprietor.id] }
  end

  def extra_filter_keys
    keys = %w[
      codigo cidade logradouro numero bairro_comercial promotion_status accepts_exchange accepts_installments key_location rental_management min_price max_price
      amenities
      permuta_vehicle permuta_property permuta_others
      situacao area_total_min area_total_max area_privativa_min area_privativa_max
      dorms_min dorms_max suites_min suites_max vagas_min vagas_max banheiros_min banheiros_max
      empreendimento_codigo corretor_id
      dashboard_quality
    ]

    if can_view_habitation_administrative_filters?
      keys += %w[
        destaque_web festival exibir_no_site exibir_no_site_portal tem_placa exclusivo regiao_foco
        foto_classificacao publicar_imovelweb_2 publicar_lais_ai
        publicar_chaves_na_mao publicar_casa_mineira publicar_imovelweb publicar_viva_real_vrsync
        tipo_publicacao_imovelweb_2 destaque_chaves_na_mao modelo_casa_mineira tipo_publicacao_imovelweb tipo_publicacao_viva_real
        captacao_inicio captacao_fim atualizacao_inicio atualizacao_fim somente_com_imagens somente_sem_imagens somente_dwv
      ]
    end

    keys
  end

  def active_extra_filters_count
    extra_filter_keys.count do |key|
      value = params[key]
      if value.is_a?(Array)
        value.reject { |item| item.blank? || I18n.transliterate(item.to_s).downcase == "todos" }.any?
      else
        value.present? && I18n.transliterate(value.to_s).downcase != "todos"
      end
    end
  end

  def clear_extra_filter_params
    request.query_parameters.except(*extra_filter_keys, "page")
  end

  def habitations_filter_session_key
    "admin_habitations_last_filter:tenant:#{current_tenant.id}:user:#{current_admin_user.id}"
  end

  def habitations_filter_session_keys
    @habitations_filter_session_keys ||= (
      %w[
        q status categoria category cidade city scope ownership intake_review visualizacao sort direction per_page
      ] + extra_filter_keys
    ).uniq
  end

  def clear_habitations_filter_session_requested?
    params[:clear_filters].to_s == "1"
  end

  def should_restore_habitations_filter_session?
    request.get? &&
      params[:page].blank? &&
      habitations_filter_session_params.present? &&
      meaningful_habitations_filter_params(request.query_parameters).blank?
  end

  def store_habitations_filter_session!
    filter_params = compact_blank_return_params(
      effective_habitations_filter_params.slice(*habitations_filter_session_keys).except("page", "clear_filters")
    )

    if meaningful_habitations_filter_params(filter_params).present?
      session[habitations_filter_session_key] = compact_habitations_filter_session_payload(filter_params)
    end
  end

  def habitations_filter_session_params
    raw_params = session[habitations_filter_session_key]
    return {} unless raw_params.respond_to?(:to_h)

    compact_blank_return_params(raw_params.to_h.slice(*habitations_filter_session_keys).except("page", "clear_filters"))
  end

  def clear_habitations_filter_session!
    session.delete(habitations_filter_session_key)
  end

  def meaningful_habitations_filter_params(source_params)
    compact_blank_return_params(
      source_params.to_h
        .slice(*habitations_filter_session_keys)
        .except("ownership", "visualizacao", "sort", "direction", "per_page", "page", "clear_filters")
    )
  end

  def effective_habitations_filter_params
    @effective_habitations_filter_params ||= begin
      filter_params = request.query_parameters.to_h
      if broker_catalog_user? &&
         !explicit_habitation_status_filter?(filter_params) &&
         meaningful_habitations_filter_params(filter_params).present?
        carried_status = habitations_filter_session_params["status"]
        carried_status.present? ? filter_params.merge("status" => carried_status) : filter_params
      else
        filter_params
      end
    end
  end

  def explicit_habitation_status_filter?(source_params = request.query_parameters)
    Array(source_params.to_h["status"]).flatten.map(&:to_s).any?(&:present?)
  end

  def should_redirect_to_effective_habitations_filter_params?
    return false unless request.get?
    return false unless broker_catalog_user?
    return false if explicit_habitation_status_filter?
    return false if meaningful_habitations_filter_params(request.query_parameters).blank?

    effective_habitations_filter_params["status"].present?
  end

  def compact_habitations_filter_session_payload(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested_value), compacted|
        compacted_value = compact_habitations_filter_session_payload(nested_value)
        compacted[key] = compacted_value unless blank_return_param?(compacted_value)
      end
    when Array
      value.first(HABITATIONS_FILTER_SESSION_MAX_ARRAY_ITEMS).filter_map do |nested_value|
        compacted_value = compact_habitations_filter_session_payload(nested_value)
        compacted_value unless blank_return_param?(compacted_value)
      end
    else
      value.to_s.strip.truncate(HABITATIONS_FILTER_SESSION_MAX_VALUE_LENGTH, omission: "").presence
    end
  end

  def extract_multi_select_integers(param_key)
    Array(params[param_key])
      .flatten
      .map { |value| value.to_s.strip }
      .reject(&:blank?)
      .map(&:to_i)
      .reject(&:zero?)
      .uniq
  end

  def excluded_commercial_neighborhood?(name)
    I18n.transliterate(name.to_s).squish.downcase == "praia brava balneario camboriu"
  end

  def parse_decimal_param(raw_value)
    value = raw_value.to_s.strip
    return nil if value.blank?

    normalized = value.gsub(/[^\d,.\-]/, '').tr(',', '.')
    decimal_value = normalized.to_f
    decimal_value.positive? ? decimal_value : nil
  end

  def load_index_filters
    @codigo = params[:codigo].to_s.strip
    @q = params[:q]
    @statuses = Array(effective_habitations_filter_params["status"]).flatten.map(&:to_s).map(&:squish).reject(&:blank?).uniq
    if permitted_habitation_filter_statuses.present?
      @statuses &= (["Todos"] + permitted_habitation_filter_statuses)
    end
    @status = @statuses.first
    @categorias = filter_values([params[:categoria], params[:category]], except: "Todas")
    @categoria = @categorias.first
    @logradouro = params[:logradouro].to_s.strip.presence
    @numero = params[:numero].to_s.strip.presence
    @cep = nil
    @cidades = filter_values([params[:cidade], params[:city]], except: "Todas")
    @cidade = @cidades.first
    @bairros = []
    @bairro = @bairros.first
    @bairros_comerciais = filter_values(params[:bairro_comercial], except: "Todos")
    @bairro_comercial = @bairros_comerciais.first
    @dorms = []
    @suites = []
    @vagas = []
    @banheiros = []
    @dorms_min = params[:dorms_min]
    @dorms_max = params[:dorms_max]
    @suites_min = params[:suites_min]
    @suites_max = params[:suites_max]
    @vagas_min = params[:vagas_min]
    @vagas_max = params[:vagas_max]
    @banheiros_min = params[:banheiros_min]
    @banheiros_max = params[:banheiros_max]
    @situacoes = filter_values(params[:situacao], except: "Todas")
    @situacao = @situacoes.first
    @face = nil
    @ocupacao_status = nil
    @estado_conservacao = nil
    @regiao_foco = params[:regiao_foco]
    @promotion_status = params[:promotion_status]
    @accepts_exchange = params[:accepts_exchange]
    @accepts_installments = params[:accepts_installments]
    @permuta_vehicle = params[:permuta_vehicle]
    @permuta_property = params[:permuta_property]
    @permuta_others = params[:permuta_others]
    @foto_classificacoes = Array(params[:foto_classificacao]).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    @permuta_location = nil
    @amenities = normalize_amenity_filter_values(params[:amenities])
    @permuta_min_dorms = nil
    @permuta_min_suites = nil
    @permuta_min_garagens = nil
    @key_location = params[:key_location]
    @rental_management = params[:rental_management]
    @empreendimento_codigos = filter_values(params[:empreendimento_codigo], except: "Todos").filter_map { |value| normalize_development_filter_value(value) }
    @empreendimento_codigo = @empreendimento_codigos.first
    @corretor_ids = can_filter_by_broker? ? catalog_filter_admin_user_ids(params[:corretor_id]) : []
    @corretor_id = @corretor_ids.first
    @corretor_filter_labels = @corretor_ids.any? ? catalog_filter_admin_users.where(id: @corretor_ids).order(:name).pluck(:name) : []
    @proprietor_id = nil
    @destaque_web = params[:destaque_web]
    @festival = params[:festival]
    @exibir_no_site = params[:exibir_no_site].presence || params[:exibir_no_site_portal]
    @publicar_imovelweb_2 = params[:publicar_imovelweb_2]
    @publicar_netimoveis_2 = params[:publicar_netimoveis_2]
    @publicar_lais_ai = params[:publicar_lais_ai]
    @publicar_loft = params[:publicar_loft]
    @publicar_chaves_na_mao = params[:publicar_chaves_na_mao]
    @publicar_casa_mineira = params[:publicar_casa_mineira]
    @publicar_imovelweb = params[:publicar_imovelweb]
    @publicar_viva_real_vrsync = params[:publicar_viva_real_vrsync]
    @tipo_publicacao_imovelweb_2 = params[:tipo_publicacao_imovelweb_2]
    @destaque_chaves_na_mao = params[:destaque_chaves_na_mao]
    @modelo_casa_mineira = params[:modelo_casa_mineira]
    @tipo_publicacao_imovelweb = params[:tipo_publicacao_imovelweb]
    @tipo_publicacao_viva_real = params[:tipo_publicacao_viva_real]
    @somente_com_imagens = params[:somente_com_imagens]
    @somente_sem_imagens = params[:somente_sem_imagens]
    @somente_dwv = params[:somente_dwv]
    @tem_placa = params[:tem_placa]
    @exclusivo = params[:exclusivo]
    @area_total_min = params[:area_total_min]
    @area_total_max = params[:area_total_max]
    @area_privativa_min = params[:area_privativa_min]
    @area_privativa_max = params[:area_privativa_max]
    @min_price = params[:min_price].to_s.gsub(/[^\d]/, '').to_i
    @max_price = params[:max_price].to_s.gsub(/[^\d]/, '').to_i
    @permuta_min_value = 0
    @scope = params[:scope]
    # Catálogo: o corretor também pode navegar todos os imóveis (curadoria), então
    # "all" é permitido para todos. O default é "all" para quem tem escopo total e
    # "mine" para os demais. Dados sensíveis por imóvel seguem gateados à parte.
    @ownership_scope = params[:ownership].presence_in(%w[mine all]) ||
                       (owns_all_resource?(:imoveis) ? "all" : "mine")
    @ownership_scope = "all" if @corretor_id.present?
    @intake_review = params[:intake_review].presence_in(%w[pending])
    @captacao_inicio = params[:captacao_inicio]
    @captacao_fim = params[:captacao_fim]
    @atualizacao_inicio = params[:atualizacao_inicio]
    @atualizacao_fim = params[:atualizacao_fim]
    @dashboard_quality = params[:dashboard_quality].presence_in(DASHBOARD_QUALITY_FILTERS)

    unless can_view_habitation_administrative_filters?
      @regiao_foco = nil
      @destaque_web = nil
      @festival = nil
      @exibir_no_site = nil
      @publicar_imovelweb_2 = nil
      @publicar_netimoveis_2 = nil
      @publicar_lais_ai = nil
      @publicar_loft = nil
      @publicar_chaves_na_mao = nil
      @publicar_casa_mineira = nil
      @publicar_imovelweb = nil
      @publicar_viva_real_vrsync = nil
      @tipo_publicacao_imovelweb_2 = nil
      @destaque_chaves_na_mao = nil
      @modelo_casa_mineira = nil
      @tipo_publicacao_imovelweb = nil
      @tipo_publicacao_viva_real = nil
      @somente_com_imagens = nil
      @somente_sem_imagens = nil
      @somente_dwv = nil
      @tem_placa = nil
      @exclusivo = nil
      @foto_classificacoes = []
      @captacao_inicio = nil
      @captacao_fim = nil
      @atualizacao_inicio = nil
      @atualizacao_fim = nil
    end
  end

  def filtered_habitations_scope
    scope = current_tenant.habitations.left_outer_joins(:address)
    scope = if @codigo.present?
              apply_ownership_scope(scope)
            elsif @intake_review == "pending"
              pending_intake_review_scope(scope)
            else
              catalog_visible_habitations_scope(scope)
            end

    if @codigo.present?
      scope = scope.where(
        "habitations.codigo = :code OR habitations.codigo_dwv = :code",
        code: @codigo
      )
    end

    scope = scope.admin_search_text(@q) if @q.present?

    scope = apply_status_filter(scope, @statuses)
    scope = apply_category_filter(scope, @categorias)
    scope = scope.where(
      "unaccent(CONCAT_WS(' ', " \
      "COALESCE(NULLIF(TRIM(addresses.tipo_endereco), ''), NULLIF(TRIM(habitations.tipo_endereco), '')), " \
      "NULLIF(TRIM(addresses.logradouro), ''), " \
      "NULLIF(TRIM(habitations.endereco), '')" \
      ")) ILIKE unaccent(?)",
      "%#{@logradouro}%"
    ) if @logradouro.present?
    scope = scope.where("COALESCE(NULLIF(TRIM(addresses.numero), ''), NULLIF(TRIM(habitations.numero), '')) ILIKE ?", "%#{@numero}%") if @numero.present?
    if @cep.present?
      cep_digits = @cep.to_s.gsub(/\D/, "")
      cep_value_sql = "COALESCE(NULLIF(TRIM(addresses.cep), ''), NULLIF(TRIM(habitations.cep), ''))"
      scope = if cep_digits.present?
                scope.where("regexp_replace(#{cep_value_sql}, '\\D', '', 'g') ILIKE ?", "%#{cep_digits}%")
              else
                scope.where("#{cep_value_sql} ILIKE ?", "%#{@cep}%")
              end
    end
    if @cidades.any?
      city_sql = "unaccent(COALESCE(NULLIF(TRIM(addresses.cidade), ''), NULLIF(TRIM(habitations.cidade), '')))"
      city_conditions = @cidades.map { "#{city_sql} = unaccent(?)" }.join(" OR ")
      scope = scope.where(city_conditions, *@cidades)
    end
    if @bairros.any?
      neighborhood_sql = "unaccent(COALESCE(NULLIF(TRIM(addresses.bairro), ''), NULLIF(TRIM(habitations.bairro), '')))"
      neighborhood_conditions = @bairros.map { "#{neighborhood_sql} ILIKE unaccent(?)" }.join(" OR ")
      scope = scope.where(neighborhood_conditions, *@bairros.map { |bairro| "%#{bairro}%" })
    end
    if @bairros_comerciais.any?
      commercial_neighborhood_sql = "unaccent(COALESCE(NULLIF(TRIM(addresses.bairro_comercial), ''), NULLIF(TRIM(habitations.bairro_comercial), '')))"
      commercial_neighborhood_conditions = @bairros_comerciais.map { "#{commercial_neighborhood_sql} ILIKE unaccent(?)" }.join(" OR ")
      scope = scope.where(commercial_neighborhood_conditions, *@bairros_comerciais.map { |bairro| "%#{bairro}%" })
    end
    scope = scope.where(dormitorios_qtd: @dorms) if @dorms.any?
    scope = scope.where(suites_qtd: @suites) if @suites.any?
    scope = scope.where(vagas_qtd: @vagas) if @vagas.any?
    scope = scope.where(banheiros_qtd: @banheiros) if @banheiros.any?
    scope = apply_integer_range_filter(scope, :dormitorios_qtd, @dorms_min, @dorms_max)
    scope = apply_integer_range_filter(scope, :suites_qtd, @suites_min, @suites_max)
    scope = apply_integer_range_filter(scope, :vagas_qtd, @vagas_min, @vagas_max)
    scope = apply_integer_range_filter(scope, :banheiros_qtd, @banheiros_min, @banheiros_max)
    scope = scope.where(situacao: @situacoes) if @situacoes.any?
    scope = scope.where(face: @face) if @face.present?
    scope = scope.where(ocupacao_status: @ocupacao_status) if @ocupacao_status.present?
    scope = scope.where(estado_conservacao: @estado_conservacao) if @estado_conservacao.present?
    if @regiao_foco == "Sim"
      scope = scope.where(
        "NULLIF(TRIM(habitations.regiao_foco), '') IS NOT NULL " \
        "AND habitations.regiao_foco != '.' " \
        "AND unaccent(habitations.regiao_foco) NOT ILIKE unaccent('Nao') " \
        "AND unaccent(habitations.regiao_foco) NOT ILIKE unaccent('Sem preferência')"
      )
    elsif @regiao_foco == "Não"
      scope = scope.where(
        "habitations.regiao_foco IS NULL OR TRIM(habitations.regiao_foco) = '' " \
        "OR habitations.regiao_foco = '.' " \
        "OR unaccent(habitations.regiao_foco) ILIKE unaccent('Nao') " \
        "OR unaccent(habitations.regiao_foco) ILIKE unaccent('Sem preferência')"
      )
    end
    @amenities.each { |amenity| scope = apply_amenity_filter(scope, amenity) } if @amenities.any?

    if @promotion_status == "with_promo"
      scope = scope.where(
        "(COALESCE(valor_venda_anterior_cents, 0) > COALESCE(valor_venda_cents, 0) AND COALESCE(valor_venda_cents, 0) > 0) OR " \
        "(COALESCE(valor_locacao_anterior_cents, 0) > COALESCE(valor_locacao_cents, 0) AND COALESCE(valor_locacao_cents, 0) > 0)"
      )
    elsif @promotion_status == "without_promo"
      scope = scope.where(
        "NOT ((COALESCE(valor_venda_anterior_cents, 0) > COALESCE(valor_venda_cents, 0) AND COALESCE(valor_venda_cents, 0) > 0) OR " \
        "(COALESCE(valor_locacao_anterior_cents, 0) > COALESCE(valor_locacao_cents, 0) AND COALESCE(valor_locacao_cents, 0) > 0))"
      )
    end

    scope = apply_boolean_filter(scope, @accepts_exchange, :aceita_permuta_flag)
    scope = apply_boolean_filter(scope, @accepts_installments, :aceita_parcelamento_flag)
    scope = apply_boolean_filter(scope, @permuta_vehicle, :aceita_permuta_veiculo_flag)
    scope = apply_boolean_filter(scope, @permuta_property, :aceita_permuta_imovel_flag)
    scope = apply_boolean_filter(scope, @permuta_others, :aceita_permuta_outros_flag)
    scope = scope.where(foto_classificacao: @foto_classificacoes) if @foto_classificacoes.any?

    if @permuta_min_value > 0
      min_permuta_cents = @permuta_min_value * 100
      scope = scope.where(
        "COALESCE(permuta_valor_cents, 0) >= :min OR COALESCE(valor_aceito_permuta_cents, 0) >= :min",
        min: min_permuta_cents
      )
    end

    scope = scope.where("unaccent(permuta_localizacao) ILIKE unaccent(?)", "%#{@permuta_location}%") if @permuta_location.present?
    scope = scope.where("COALESCE(permuta_dormitorios_qtd, 0) >= ?", @permuta_min_dorms.to_i) if @permuta_min_dorms.present?
    scope = scope.where("COALESCE(permuta_suites_qtd, 0) >= ?", @permuta_min_suites.to_i) if @permuta_min_suites.present?
    scope = scope.where("COALESCE(permuta_garagens_qtd, 0) >= ?", @permuta_min_garagens.to_i) if @permuta_min_garagens.present?
    scope = scope.where(key_location: @key_location) if @key_location.present?
    if @empreendimento_codigos.any?
      scope = @empreendimento_codigos.reduce(scope.none) do |combined_scope, value|
        combined_scope.or(apply_development_filter(scope, value))
      end
    end
    if @corretor_ids.any?
      scope = scope.where(
        "EXISTS (
           SELECT 1
	         FROM habitation_broker_assignments
	         WHERE habitation_broker_assignments.habitation_id = habitations.id
	           AND habitation_broker_assignments.admin_user_id IN (:ids)
	         ) OR habitations.admin_user_id IN (:ids)",
	        ids: @corretor_ids
      )
    end
    scope = scope.where(proprietor_id: @proprietor_id) if @proprietor_id.present?

    scope = apply_boolean_filter(scope, @rental_management, :rental_management_flag)
    scope = apply_price_range_filter(scope)

    captacao_inicio = parse_date_param(@captacao_inicio)
    captacao_fim = parse_date_param(@captacao_fim)
    if captacao_inicio
      scope = scope.where("COALESCE(habitations.data_cadastro_crm, habitations.created_at) >= ?", captacao_inicio.beginning_of_day)
    end
    if captacao_fim
      scope = scope.where("COALESCE(habitations.data_cadastro_crm, habitations.created_at) <= ?", captacao_fim.end_of_day)
    end

    atualizacao_inicio = parse_date_param(@atualizacao_inicio)
    atualizacao_fim = parse_date_param(@atualizacao_fim)
    if atualizacao_inicio
      scope = scope.where("COALESCE(habitations.data_atualizacao_crm, habitations.updated_at) >= ?", atualizacao_inicio.beginning_of_day)
    end
    if atualizacao_fim
      scope = scope.where("COALESCE(habitations.data_atualizacao_crm, habitations.updated_at) <= ?", atualizacao_fim.end_of_day)
    end

    area_total_min = parse_decimal_param(@area_total_min)
    area_total_max = parse_decimal_param(@area_total_max)
    area_privativa_min = parse_decimal_param(@area_privativa_min)
    area_privativa_max = parse_decimal_param(@area_privativa_max)

    scope = scope.where("area_total_m2 >= ?", area_total_min) if area_total_min
    scope = scope.where("area_total_m2 <= ?", area_total_max) if area_total_max
    scope = scope.where("area_privativa_m2 >= ?", area_privativa_min) if area_privativa_min
    scope = scope.where("area_privativa_m2 <= ?", area_privativa_max) if area_privativa_max
    scope = apply_boolean_filter(scope, @destaque_web, :destaque_web_flag)
    scope = apply_boolean_filter(scope, @festival, :festival_flag)
    scope = apply_boolean_filter(scope, @exibir_no_site, :exibir_no_site_flag)
    scope = apply_boolean_filter(scope, @publicar_imovelweb_2, :publicar_imovelweb_2)
    scope = apply_boolean_filter(scope, @publicar_netimoveis_2, :publicar_netimoveis_2)
    scope = apply_boolean_filter(scope, @publicar_lais_ai, :publicar_lais_ai)
    scope = apply_boolean_filter(scope, @publicar_loft, :publicar_loft)
    scope = apply_boolean_filter(scope, @publicar_chaves_na_mao, :publicar_chaves_na_mao)
    scope = apply_boolean_filter(scope, @publicar_casa_mineira, :publicar_casa_mineira)
    scope = apply_boolean_filter(scope, @publicar_imovelweb, :publicar_imovelweb)
    scope = apply_boolean_filter(scope, @publicar_viva_real_vrsync, :publicar_viva_real_vrsync)
    scope = apply_text_option_filter(scope, @tipo_publicacao_imovelweb_2, :tipo_publicacao_imovelweb_2)
    scope = apply_text_option_filter(scope, @destaque_chaves_na_mao, :destaque_chaves_na_mao)
    scope = apply_text_option_filter(scope, @modelo_casa_mineira, :modelo_casa_mineira)
    scope = apply_text_option_filter(scope, @tipo_publicacao_imovelweb, :tipo_publicacao_imovelweb)
    scope = apply_text_option_filter(scope, @tipo_publicacao_viva_real, :tipo_publicacao_viva_real)

    if @somente_com_imagens == "1" && @somente_sem_imagens != "1"
      scope = scope.with_photos
    elsif @somente_sem_imagens == "1" && @somente_com_imagens != "1"
      scope = scope.where.not(id: Habitation.with_photos.select(:id))
    end

    if @somente_dwv == "1"
      scope = scope.where("LOWER(TRIM(COALESCE(habitations.imovel_dwv, ''))) = ?", "sim")
    end

    scope = apply_dashboard_quality_filter(scope, @dashboard_quality)

    scope = apply_boolean_filter(scope, @tem_placa, :tem_placa_flag)
    scope = apply_boolean_filter(scope, @exclusivo, :exclusivo_flag)

    scope = apply_quick_scope_filter(scope, @scope)
    scope = apply_broker_catalog_availability_filter(scope)

    scope
  end

  def load_pwa_habitation_nav_counts
    all_scope = pwa_habitation_catalog_scope_for("all")
    mine_scope = current_admin_user ? pwa_habitation_catalog_scope_for("mine") : current_tenant.habitations.none

    @pwa_habitation_nav_counts = {
      all: pwa_habitation_count(all_scope),
      mine: pwa_habitation_count(mine_scope),
      sale: pwa_habitation_count(pwa_habitation_sale_scope(all_scope)),
      rent: pwa_habitation_count(pwa_habitation_rent_scope(all_scope)),
      opportunity: pwa_habitation_count(apply_quick_scope_filter(all_scope, "oportunidade"))
    }
  end

  def pwa_habitation_catalog_scope_for(ownership_scope)
    previous_ownership_scope = @ownership_scope
    @ownership_scope = ownership_scope
    apply_broker_catalog_availability_filter(
      catalog_visible_habitations_scope(current_tenant.habitations.left_outer_joins(:address))
    )
  ensure
    @ownership_scope = previous_ownership_scope
  end

  def pwa_habitation_count(scope)
    scope.distinct.count(:id)
  end

  def pwa_habitation_sale_scope(scope)
    scope.where(
      "COALESCE(habitations.valor_venda_cents, 0) > 0 OR unaccent(COALESCE(habitations.status, '')) ILIKE unaccent(?)",
      "%venda%"
    )
  end

  def pwa_habitation_rent_scope(scope)
    scope.where(
      "COALESCE(habitations.valor_locacao_cents, 0) > 0 OR unaccent(COALESCE(habitations.status, '')) ILIKE unaccent(?) OR unaccent(COALESCE(habitations.status, '')) ILIKE unaccent(?)",
      "%aluguel%",
      "%loca%"
    )
  end

  def apply_broker_catalog_availability_filter(scope)
    return scope unless broker_catalog_user?
    return scope if all_habitation_statuses_filter_requested?
    return scope if inactive_habitation_status_filter_requested?

    scope.commercially_publishable
  end

  def all_habitation_statuses_filter_requested?
    @statuses.any? { |status| I18n.transliterate(status.to_s).downcase == "todos" }
  end

  def inactive_habitation_status_filter_requested?
    @statuses.any? do |status|
      next false if I18n.transliterate(status.to_s).downcase == "todos"

      normalized = Habitation.normalize_status(status).to_s
      I18n.transliterate(normalized.presence || status.to_s)
        .downcase
        .match?(Regexp.new(Habitation::INACTIVE_COMMERCIAL_STATUS_REGEX))
    end
  end

  def apply_dashboard_quality_filter(scope, filter)
    return scope.where.not(id: Habitation.with_photos.select(:id)) if filter == "missing_photos"
    return scope.without_operational_price if filter == "missing_price"

    scope = scope.publicly_listable if filter.present?

    case filter
    when "missing_address"
      scope.without_operational_address
    when "stale"
      scope.where("COALESCE(habitations.data_atualizacao_crm, habitations.updated_at) < ?", 90.days.ago)
    else
      scope
    end
  end

  def apply_development_filter(scope, raw_value)
    parsed = Admin::HabitationDevelopmentFilterOptions.parse(raw_value)
    value = parsed[:value].to_s.strip
    return scope if value.blank?

    matching_developments = matching_developments_for_filter(parsed[:type], value)
    matched_codes = matching_developments.pluck(:codigo).map { |code| code.to_s.strip }.reject(&:blank?).uniq
    matched_names = matching_developments.pluck(:nome_empreendimento).map { |name| normalize_development_filter_name(name) }.reject(&:blank?).uniq
    matched_names << normalize_development_filter_name(value)
    matched_names.compact_blank!

    clauses = []
    binds = {}

    if matched_codes.any?
      clauses << "(habitations.codigo_empreendimento IN (:codes) OR habitations.codigo IN (:codes))"
      binds[:codes] = matched_codes
    end

    if matched_names.any?
      clauses << "LOWER(unaccent(COALESCE(habitations.nome_empreendimento, ''))) IN (:names)"
      binds[:names] = matched_names
    end

    return scope if clauses.empty?

    scope.where(clauses.join(" OR "), binds)
  end

  def matching_developments_for_filter(type, value)
    developments = current_tenant.habitations.empreendimentos
    named_match = developments.where("LOWER(unaccent(nome_empreendimento)) = LOWER(unaccent(:name))", name: value)

    case type
    when :development
      developments.where(codigo: value).or(named_match)
    when :standalone, :legacy
      named_match
    else
      developments.where(codigo: value).or(named_match)
    end
  end

  def normalize_development_filter_value(raw_value)
    parsed = Admin::HabitationDevelopmentFilterOptions.parse(raw_value)
    value = parsed[:value].to_s.strip
    return nil if value.blank?
    return raw_value if parsed[:type] != :legacy

    if current_tenant.habitations.empreendimentos.exists?(codigo: value)
      Admin::HabitationDevelopmentFilterOptions.development_value(value)
    else
      raw_value
    end
  end

  def normalize_development_filter_name(value)
    I18n.transliterate(value.to_s).squish.downcase
  end

  def index_per_page
    requested = params[:per_page].to_i
    INDEX_PAGE_SIZE_OPTIONS.include?(requested) ? requested : DEFAULT_INDEX_PAGE_SIZE
  end

  def apply_ownership_scope(scope)
    return scope if @ownership_scope == "all"
    return scope unless current_admin_user

    # O escopo do perfil é a fonte de verdade. Em `team`, a listagem sempre usa
    # a subárvore completa; não existe opt-out por query param nesta tela.
    owner_ids = accessible_owner_ids(:imoveis)
    return scope if owner_ids.nil? # escopo total (não deveria cair aqui, mas é defensivo)

    if owner_ids == [current_admin_user.id]
      scope_for_current_user_properties(scope)
    else
      team_property_scope(scope, owner_ids)
    end
  end

  # Imóveis pertencentes à equipe (subárvore): dono direto ou corretor designado.
  def team_property_scope(scope, owner_ids)
    scope.where(
      "habitations.admin_user_id IN (:ids) OR EXISTS (
        SELECT 1
        FROM habitation_broker_assignments
        WHERE habitation_broker_assignments.habitation_id = habitations.id
          AND habitation_broker_assignments.admin_user_id IN (:ids)
      )",
      ids: owner_ids
    )
  end

  def scope_for_current_user_properties(scope)
    return scope unless current_admin_user

    broker_name = current_admin_user.name.to_s.strip
    broker_name_condition = broker_name.present? ? " OR habitations.corretor_nome ILIKE :name" : ""
    scope.where(
      "habitations.admin_user_id = :id#{broker_name_condition}",
      id: current_admin_user.id,
      name: "%#{broker_name}%"
    )
  end

  def catalog_visible_habitations_scope(scope)
    scope = scope.where(
      "habitations.intake_origin IS NULL OR habitations.intake_origin != :broker_origin OR habitations.intake_status IN (:visible_statuses)",
      broker_origin: Habitation::INTAKE_ORIGIN_BROKER,
      visible_statuses: Habitation::CATALOG_VISIBLE_INTAKE_STATUSES
    )
    apply_ownership_scope(scope)
  end

  def pending_intake_review_scope(scope)
    review_statuses = if can_review_intakes?
                        %w[submitted_for_admin_review admin_approved]
                      else
                        %w[draft submitted_for_admin_review admin_approved]
                      end
    scope = scope.broker_intakes.where(intake_status: review_statuses)

    if can_review_intakes?
      return restrict_pending_review_to_manager_team(scope) if current_admin_user&.can_view_team?(:captacoes) && !owns_all_resource?(:captacoes) && !tenant_owner?

      scope
    else
      scope_for_current_user_properties(scope)
    end
  end

  def normalized_report_type
    report_type = params[:report_type].to_s
    REPORT_TYPES.key?(report_type) ? report_type : "property_list"
  end

  def sanitized_selected_ids
    values = params[:selected_ids]
    array = values.is_a?(String) ? values.split(",") : Array(values)
    array.map(&:to_i).select(&:positive?)
  end

  # Retorna os IDs alvos do bulk. Se o usuário marcou \"selecionar tudo\",
  # reconstruímos a base filtrada (respeitando filtros ativos) e pegamos
  # todos os IDs. Caso contrário, usa só os IDs marcados individualmente.
  def resolve_bulk_ids
    if ActiveModel::Type::Boolean.new.cast(params[:select_all_filtered])
      # Reaplica os mesmos filtros da listagem — params[:filters] vem como hash
      # das query params originais.
      reapply_filter_params!
      load_index_filters
      filtered_habitations_scope.reorder(nil).pluck(:id)
    else
      sanitized_selected_ids
    end
  end

  def reapply_filter_params!
    filters = params[:filters]
    return unless filters.respond_to?(:each)
    filters.each do |key, value|
      next if params.key?(key)  # não sobrescreve params já setados
      params[key] = value
    end
  end

  def sanitized_export_fields
    selected = Array(params[:fields]).map(&:to_s)
    valid = selected.select { |field| EXPORT_FIELDS.key?(field) }
    valid -= %w[proprietario] unless can_export_proprietor_data?
    valid.presence || %w[codigo categoria logradouro numero complemento dormitorios_qtd valor_venda valor_locacao]
  end

  def export_col_sep
    params[:data_format].to_s == "csv_comma" ? "," : ";"
  end

  def export_json(export)
    {
      id: export.id,
      filename: export.filename,
      status: export.status,
      progress: export.progress,
      record_count: export.record_count,
      created_at: export.created_at.strftime("%d/%m %H:%M"),
      ready: export.ready?,
      error: export.error_message,
      download_url: (export.ready? ? download_export_admin_habitations_path(export_id: export.id) : nil)
    }
  end

  # Mantém apenas as 5 exportações mais recentes do usuário.
  def prune_old_exports!
    current_admin_user.habitation_exports.recent.offset(5).each do |old|
      old.file.purge_later if old.file.attached?
      old.destroy
    end
  end

  def record_data_export!(export_type:, format:, record_count:, selected_count:, fields:, filters:, filename: nil, metadata: {})
    Audit::DataExportRecorder.call(
      admin_user: current_admin_user,
      request: request,
      export_type: export_type,
      resource_name: "habitations",
      format: format,
      record_count: record_count,
      selected_count: selected_count,
      filename: filename,
      filters: filters,
      fields: fields,
      metadata: metadata
    )
  end

  def data_export_filters
    params.to_unsafe_h.slice(
      "q", "status", "categoria", "tipo", "bairro", "cidade", "codigo", "corretor",
      "selected_ids", "report_type", "data_format", "fields", "sort", "direction"
    )
  end

  def record_catalog_user_activity
    return unless request.format.html?

    filters = request.query_parameters
    event_name = catalog_filter_activity?(filters) ? "catalog_search" : "property_list_viewed"
    record_user_activity!(
      event_name,
      query_text: [@q, @codigo].compact_blank.join(" ").presence,
      filter_params: filters,
      result_count: @filtered_count,
      visible_habitation_ids: @habitations.map(&:id),
      metadata: {
        source: "admin_habitations_index",
        view_mode: params[:visualizacao].to_s == "tabela" ? "tabela" : "cards",
        page: @habitations.current_page,
        per_page: @per_page,
        page_count: @habitations.size,
        sort: @sort_column,
        direction: @sort_direction
      }
    )
  end

  def catalog_filter_activity?(filters)
    ignored_keys = %w[ownership visualizacao page per_page sort direction back_anchor return_to]
    filters.except(*ignored_keys).any? { |_key, value| audit_filter_value_present?(value) }
  end

  def audit_filter_value_present?(value)
    case value
    when Hash
      value.any? { |_key, item| audit_filter_value_present?(item) }
    when Array
      value.any? { |item| audit_filter_value_present?(item) }
    else
      value.present?
    end
  end

  def data_export_count_for(scope)
    return @habitations.size if single_habitation_sheet_report? && defined?(@habitations)
    return @broker_rows.size if defined?(@broker_rows) && @broker_rows.present?
    return @summary_rows.size if defined?(@summary_rows) && @summary_rows.present?

    scope.count
  end

  def export_row(habitation, fields)
    fields.map do |field|
      case field
      when "codigo" then habitation.codigo
      when "categoria" then habitation.categoria
      when "status" then habitation.status
      when "logradouro" then habitation.logradouro || habitation.endereco
      when "numero" then habitation.numero
      when "complemento" then habitation.complemento
      when "bairro" then habitation.bairro
      when "cidade" then habitation.cidade
      when "uf" then habitation.uf
      when "cep" then habitation.cep
      when "dormitorios_qtd" then habitation.dormitorios_qtd
      when "suites_qtd" then habitation.suites_qtd
      when "banheiros_qtd" then habitation.banheiros_qtd
      when "vagas_qtd" then habitation.vagas_qtd
      when "valor_venda" then habitation.valor_venda_formatted
      when "valor_locacao" then habitation.valor_locacao_formatted
      when "valor_condominio" then habitation.valor_condominio_formatted
      when "valor_iptu" then habitation.valor_iptu_formatted
      when "area_privativa_m2" then habitation.area_privativa_m2
      when "area_total_m2" then habitation.area_total_m2
      when "valor_por_m2" then habitation.valor_por_m2_formatted
      when "corretor_nome" then habitation.corretor_nome
      when "proprietario" then can_view_proprietor_data?(habitation) ? habitation.proprietario : "Captador: #{habitation.admin_user&.name || habitation.corretor_nome}"
      when "codigo_empreendimento" then habitation.codigo_empreendimento
      else habitation.public_send(field)
      end
    end
  end

  def can_view_proprietor_data?(habitation)
    return true if can_access_sensitive_habitation_data?
    return manager_can_view_proprietor_data?(habitation) if current_admin_user&.can_view_team?(:imoveis)

    property_belongs_to_current_user?(habitation)
  end

  def can_view_internal_documents?(habitation)
    return true if can_access_sensitive_habitation_data?
    return manager_can_view_proprietor_data?(habitation) if current_admin_user&.can_view_team?(:imoveis)

    property_belongs_to_current_user?(habitation)
  end

  def can_view_habitation_show_sensitive_data?(habitation)
    return true if can_access_sensitive_habitation_data?
    return manager_can_view_proprietor_data?(habitation) if current_admin_user&.can_view_team?(:imoveis)

    false
  end

  def can_view_habitation_owner_contact_data?(habitation)
    return true if can_access_sensitive_habitation_data?
    return manager_can_view_proprietor_data?(habitation) if current_admin_user&.can_view_team?(:imoveis)

    property_captured_by_current_user?(habitation)
  end

  def can_edit_habitation?(habitation)
    return false unless property_accessible?(habitation)
    return false unless habitation_matches_current_user_acting_type?(habitation)

    can?(:edit, :imoveis) || property_belongs_to_current_user?(habitation)
  end

  # Acesso a um imóvel: dono direto / corretor designado / nome do corretor (próprio),
  # ou — quando o perfil tem escopo de equipe — imóvel pertencente à subárvore de gestão.
  def property_accessible?(habitation)
    return true if owns_all_resource?(:imoveis)
    return true if property_belongs_to_current_user?(habitation)
    return false unless current_admin_user&.can_view_team?(:imoveis)

    property_owned_by_team?(habitation)
  end

  def property_owned_by_team?(habitation)
    ids = manager_team_user_ids
    return true if ids.include?(habitation.admin_user_id)
    return true if property_matches_team_broker_name?(habitation, ids)

    habitation.broker_assignments.exists?(admin_user_id: ids)
  end

  def property_matches_team_broker_name?(habitation, team_ids)
    return false if team_ids.blank?

    broker_names = team_broker_names_for(team_ids)
    return false if broker_names.blank?

    candidates = [
      habitation.corretor_nome,
      (habitation.primary_captador_name if habitation.respond_to?(:primary_captador_name))
    ].compact_blank.map { |value| normalize_broker_match_text(value) }

    candidates.any? do |candidate|
      broker_names.any? { |broker_name| candidate.include?(broker_name) }
    end
  end

  def team_broker_names_for(team_ids)
    @team_broker_names_by_scope ||= {}
    key = team_ids.map(&:to_i).sort
    @team_broker_names_by_scope[key] ||= current_tenant
      .admin_users
      .where(id: key)
      .pluck(:name)
      .compact_blank
      .map { |name| normalize_broker_match_text(name) }
      .select(&:present?)
  end

  def normalize_broker_match_text(value)
    I18n.transliterate(value.to_s).downcase.squish
  end

  def can_release_intake_to_broker?(habitation)
    return false unless habitation&.broker_intake?
    return false if habitation.intake_draft? || habitation.intake_published?

    can_complete_admin_intake_review?(habitation)
  end

  def can_complete_admin_intake_review?(habitation)
    return false unless habitation&.broker_intake?

    can_review_captacao?(habitation)
  end

  def can_review_intakes?
    can?(:review, :captacoes)
  end

  def can_manage_intake_status?(habitation)
    return false unless habitation&.broker_intake?

    can_review_captacao?(habitation)
  end

  def can_manage_internal_documents?
    can_access_sensitive_habitation_data?
  end

  def no_duplicate_address?(habitation)
    result = HabitationDuplicateChecker.new(
      street: habitation.logradouro,
      number: habitation.numero,
      building: habitation.nome_empreendimento,
      unit: habitation.bloco,
      status: habitation.status,
      complement: habitation.complemento,
      category: habitation.categoria,
      lot: habitation.lote,
      block_section: habitation.respond_to?(:quadra) ? habitation.quadra : nil,
      development_code: habitation.codigo_empreendimento,
      comparison: habitation.duplicate_identity_scope,
      ignored_id: habitation.id,
      tenant: Current.tenant
    ).call
    return true unless result.complete && result.duplicate?

    duplicated = result.matches.first
    code = duplicated&.codigo.present? ? " ##{duplicated.codigo}" : ""
    message = if habitation.duplicate_identity_scope == :unit
                "Já existe imóvel cadastrado com esta rua, número, unidade e status comercial#{code}."
              elsif habitation.duplicate_identity_scope == :condominium_unit && habitation.property_kind_terreno?
                "Já existe terreno cadastrado com esta rua, número, complemento, lote, quadra e status comercial#{code}."
              elsif habitation.duplicate_identity_scope == :condominium_unit
                "Já existe casa em condomínio cadastrada com esta rua, número, unidade, lote, quadra e status comercial#{code}."
              else
                "Já existe imóvel cadastrado com esta rua, número e status comercial#{code}."
              end
    habitation.errors.add(:base, message)
    habitation.errors.add(:"address.logradouro", message)
    habitation.errors.add(:"address.numero", message)
    habitation.errors.add(:bloco, message) if habitation.duplicate_identity_scope.in?(%i[unit condominium_unit])
    false
  end

  def release_intake_to_broker_requested?
    params[:release_to_broker_after_save].present?
  end

  def save_internal_intake_requested?
    params[:save_internal_after_save].present?
  end

  def redirect_after_habitation_save(habitation, notice:)
    anchor = params[:save_anchor].to_s.presence_in(%w[documents media])

    if source_habitation.present? && habitation.empreendimento?
      redirect_to admin_path_with_flat_return(edit_admin_habitation_path(source_habitation.id), safe_admin_habitations_return_path(params[:return_to])), notice: "#{notice} Unidade vinculada ao empreendimento #{habitation.codigo}."
      return
    end

    if params[:save_context].to_s == "media_module"
      redirect_to admin_path_with_flat_return(admin_habitation_media_path(habitation.id), safe_admin_habitations_return_path(params[:return_to])), notice: notice
      return
    end

    if params[:save_navigation].to_s == "stay"
      redirect_to admin_path_with_flat_return(edit_admin_habitation_path(habitation.id, anchor: anchor), safe_admin_habitations_return_path(params[:return_to])), notice: "#{notice} Você permaneceu na ficha de cadastro."
    else
      redirect_to safe_admin_habitations_return_path(params[:return_to]) || admin_habitations_path, notice: "#{notice} Você saiu para o catálogo."
    end
  end

  def edit_habitation_path_with_return(habitation, anchor:)
    admin_path_with_flat_return(
      edit_admin_habitation_path(habitation.id, anchor: anchor),
      safe_admin_habitations_return_path(params[:return_to])
    )
  end

  def admin_path_with_flat_return(path, return_to)
    helpers.admin_habitation_path_with_query(
      path,
      helpers.admin_habitation_flat_return_params(return_to)
    )
  end

  def touch_manual_habitation_update!(habitation, force: false)
    habitation.data_atualizacao_crm = Time.current if force || habitation.changed?
  end

  def safe_admin_habitations_return_path(value, source_params: params)
    path = value.to_s.strip
    return nil if path.blank?

    uri = URI.parse(path)
    return nil if uri.scheme.present? || uri.host.present?
    return nil unless safe_admin_habitation_return_path?(uri.path)

    query_params = Rack::Utils.parse_nested_query(uri.query.to_s)
    query_params.merge!(flattened_admin_habitations_return_query_params(source_params))
    query = compact_return_query(Rack::Utils.build_nested_query(query_params))
    path_with_query = [uri.path, query].compact.join("?")
    fragment = uri.fragment.presence || source_params[:back_anchor].to_s.presence || source_params["back_anchor"].to_s.presence
    fragment.present? ? "#{path_with_query}##{fragment}" : path_with_query
  rescue URI::InvalidURIError
    nil
  end

  def flattened_admin_habitations_return_query_params(source_params)
    raw_params =
      if source_params.respond_to?(:to_unsafe_h)
        source_params.to_unsafe_h
      else
        source_params.to_h
      end

    raw_params
      .except(*RETURN_PARAM_DENYLIST)
      .compact_blank
  end

  def safe_admin_habitation_return_path?(path)
    path == admin_habitations_path ||
      path == admin_leads_path ||
      path.match?(%r{\A/admin/leads/\d+\z})
  end

  def compact_return_query(query)
    compacted = compact_blank_return_params(Rack::Utils.parse_nested_query(query.to_s))
    return nil if blank_return_param?(compacted)

    Rack::Utils.build_nested_query(compacted)
  end

  def compact_blank_return_params(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested_value), compacted_hash|
        compacted_value = compact_blank_return_params(nested_value)
        compacted_hash[key] = compacted_value unless blank_return_param?(compacted_value)
      end
    when Array
      value.filter_map do |nested_value|
        compacted_value = compact_blank_return_params(nested_value)
        compacted_value unless blank_return_param?(compacted_value)
      end
    else
      value.to_s.strip.presence
    end
  end

  def blank_return_param?(value)
    value.blank? || (value.respond_to?(:empty?) && value.empty?)
  end

  def keep_admin_review_intake_hidden
    return unless @habitation.broker_intake?
    return if @habitation.intake_internal? || @habitation.intake_published?

    @habitation.exibir_no_site_flag = false
  end

  def admin_paper_intake_form?
    admin_paper_intake_requested? && can_create_internal_intake?
  end

  def can_create_internal_intake?
    tenant_owner? || owns_all_resource?(:captacoes)
  end

  def admin_paper_intake_requested?
    params[:intake_mode].to_s == "paper" || release_intake_to_broker_requested? || save_internal_intake_requested?
  end

  def prepare_development_from_source(habitation)
    source = source_habitation
    return unless source.present?

    habitation.tipo = "Empreendimento"
    habitation.categoria = "Empreendimento"
    habitation.status ||= source.status.presence || "Venda"
    habitation.nome_empreendimento ||= source.nome_empreendimento.presence
    habitation.proprietor_id ||= source.proprietor_id
    habitation.admin_user_id ||= source.admin_user_id
    habitation.data_entrega ||= source.data_entrega
    habitation.perfil_construcao ||= source.perfil_construcao
  end

  def assign_new_habitation_defaults(habitation)
    defaults = params.fetch(:habitation, ActionController::Parameters.new).permit(:registration_profile, :tipo, :categoria, :status)
    normalize_registration_profile_selection!(defaults)
    defaults[:status] = "Venda" if defaults[:status].blank?
    habitation.assign_attributes(defaults)
  end

  def admin_habitation_profile_started?
    params.dig(:habitation, :registration_profile).present? ||
      params.dig(:habitation, :categoria).present? ||
      params.dig(:habitation, :status).present?
  end

  def default_category_for_registration_profile(profile)
    Habitation::REGISTRATION_PROFILES.dig(profile.to_s, :categories)&.first
  end

  def default_tipo_for_registration_profile(profile)
    Habitation::REGISTRATION_PROFILES.dig(profile.to_s, :tipo)
  end

  def normalize_registration_profile_selection!(attributes)
    profile = attributes[:registration_profile].to_s.presence_in(Habitation::REGISTRATION_PROFILE_KEYS)

    if profile.blank?
      attributes.delete(:registration_profile)
      return attributes
    end

    config = Habitation::REGISTRATION_PROFILES.fetch(profile)
    categories = config.fetch(:categories)
    attributes[:categoria] = Habitation.normalize_registration_category(attributes[:categoria])

    attributes[:registration_profile] = profile
    attributes[:tipo] = config.fetch(:tipo)
    attributes[:categoria] = categories.first unless attributes[:categoria].to_s.in?(categories)
    attributes
  end

  def link_source_habitation_to_development!(development)
    source = source_habitation
    return unless source.present?
    return unless development.empreendimento?
    return if development.codigo.blank?

    source.update!(codigo_empreendimento: development.codigo)
  end

  def source_habitation
    return @source_habitation if defined?(@source_habitation)

    id = params[:source_habitation_id].presence
    @source_habitation = nil
    return @source_habitation if id.blank?

    candidate = current_tenant.habitations.find_by(id: id)
    @source_habitation = candidate if candidate.present? && can_edit_habitation?(candidate) && !candidate.empreendimento?
  end

  def prepare_admin_paper_intake(habitation)
    habitation.intake_origin ||= Habitation::INTAKE_ORIGIN_BROKER
    habitation.intake_status ||= "draft"
    habitation.admin_user ||= current_admin_user
    habitation.exibir_no_site_flag = false unless habitation.intake_internal? || habitation.intake_published?
  end

  def mark_intake_as_admin_approved(habitation)
    reviewed_at = Time.current
    habitation.finalize_broker_intake_registration!(submitted_at: habitation.submitted_for_review_at.presence || reviewed_at)
    habitation.intake_status = "admin_approved"
    habitation.admin_reviewed_by = current_admin_user
    habitation.admin_reviewed_at = reviewed_at
    habitation.exibir_no_site_flag = false
  end

  def mark_intake_as_internal(habitation)
    reviewed_at = Time.current
    habitation.finalize_broker_intake_registration!(submitted_at: habitation.submitted_for_review_at.presence || reviewed_at)
    habitation.intake_status = "internal"
    habitation.admin_reviewed_by = current_admin_user
    habitation.admin_reviewed_at = reviewed_at
    habitation.exibir_no_site_flag = false
  end

  def apply_intake_status_transition_metadata(habitation)
    return unless habitation.broker_intake?
    return unless habitation.will_save_change_to_intake_status?

    case habitation.intake_status
    when "submitted_for_admin_review"
      habitation.submitted_for_review_at ||= Time.current
      habitation.exibir_no_site_flag = false
    when "admin_approved"
      habitation.admin_reviewed_by ||= current_admin_user
      habitation.admin_reviewed_at ||= Time.current
      habitation.exibir_no_site_flag = false
    when "internal"
      habitation.admin_reviewed_by ||= current_admin_user
      habitation.admin_reviewed_at ||= Time.current
      habitation.exibir_no_site_flag = false
    when "returned_to_broker"
      habitation.admin_reviewed_by ||= current_admin_user
      habitation.admin_reviewed_at ||= Time.current
      habitation.exibir_no_site_flag = false
    when "published"
      habitation.broker_released_at ||= Time.current
      habitation.exibir_no_site_flag = true
    else
      habitation.exibir_no_site_flag = false
    end
  end

  def apply_boolean_filter(scope, raw_param, column_name)
    physical_name = Habitation.physical_column_name(column_name)
    column = ActiveRecord::Base.connection.quote_column_name(physical_name)
    case raw_param
    when '1' then scope.where("habitations.#{column} IS TRUE")
    when '0' then scope.where("habitations.#{column} IS NOT TRUE")
    else scope
    end
  end

  def apply_text_option_filter(scope, raw_param, column_name)
    value = raw_param.to_s.squish
    return scope if value.blank?

    physical_name = Habitation.physical_column_name(column_name)
    column = ActiveRecord::Base.connection.quote_column_name(physical_name)
    scope.where("LOWER(TRIM(habitations.#{column})) = ?", value.downcase)
  end

  def apply_status_filter(scope, raw_statuses)
    statuses = Array(raw_statuses).flatten.map(&:to_s).map(&:squish).reject(&:blank?).uniq
    return scope if statuses.blank?
    return scope if statuses.any? { |status| I18n.transliterate(status).downcase == "todos" }

    normalized_statuses = statuses
      .map { |status| Habitation.normalize_status(status) }
      .compact_blank
      .uniq

    conditions = normalized_statuses.map { "unaccent(TRIM(habitations.status)) = unaccent(?)" }
    values = normalized_statuses.dup
    return scope if conditions.blank?

    scope.where(conditions.join(" OR "), *values)
  end

  def apply_category_filter(scope, raw_categories)
    categories = filter_values(raw_categories, except: "Todas")
    return scope if categories.blank?

    categories.reduce(scope.none) do |combined_scope, category|
      normalized_category = I18n.transliterate(category).downcase

      category_scope = case normalized_category
                       when "apartamento"
                         scope.where("unaccent(habitations.categoria) ILIKE unaccent(?)", "%apartamento%")
                       when "casa"
                         scope.where("unaccent(habitations.categoria) IN (unaccent('Casa'), unaccent('Casa de Rua'))")
                       when "casa em condominio"
                         scope.where("unaccent(habitations.categoria) ILIKE unaccent(?)", "%casa%condominio%")
                       when "sala comercial"
                         scope.where("unaccent(habitations.categoria) ILIKE unaccent(?)", "%sala%comercial%")
                       when "terreno"
                         scope.where("unaccent(habitations.categoria) ILIKE unaccent(?)", "%terreno%")
                       when "empreendimento"
                         scope.where(tipo: "Empreendimento")
                       when "garden"
                         scope.garden
                       when "diferenciado"
                         scope.diferenciado
                       else
                         scope.where("unaccent(TRIM(habitations.categoria)) = unaccent(?)", category)
                       end

      combined_scope.or(category_scope)
    end
  end

  def apply_quick_scope_filter(scope, raw_scope)
    case raw_scope
    when "destaque_web"
      scope.where(destaque_web_flag: true)
    when "super_destaque"
      scope.where(Habitation.physical_column_name(:festival_flag) => true)
    when "oportunidade"
      scope.opportunity
    when "frente_mar"
      apply_front_sea_filter(scope)
    when "lancamento"
      scope.where(lancamento_flag: true)
    when "na_planta"
      scope.where("unaccent(COALESCE(habitations.situacao, '')) ILIKE unaccent(?) OR unaccent(COALESCE(habitations.situacao, '')) = unaccent(?)", "%Planta%", "Construção")
    when "mobiliado"
      apply_catalog_text_feature_filter(scope, "mobiliado", boolean_column: :mobiliado_flag)
    when "semi_mobiliado"
      scope.semi_mobiliado
    when "sem_mobilia"
      apply_catalog_text_feature_filter(scope, "sem mob", boolean_column: :sem_mobilia_flag)
    when "diferenciado"
      scope.diferenciado
    when "quadra_mar"
      scope.quadra_mar
    when "dependencia_empregada"
      scope.dependencia_empregada
    when "cozinha_gourmet_churrasqueira"
      scope.cozinha_gourmet_churrasqueira
    when "sol_manha"
      scope.sol_manha
    when "sol_tarde"
      scope.sol_tarde
    when "sol_dia_todo"
      scope.sol_dia_todo
    when "decorado"
      apply_catalog_text_feature_filter(scope, "decorad", boolean_column: :decorado_flag)
    else
      scope
    end
  end

  def apply_price_range_filter(scope)
    return scope unless @min_price.positive? || @max_price.positive?

    sale_conditions = ["COALESCE(valor_venda_cents, 0) > 0"]
    rent_conditions = ["COALESCE(valor_locacao_cents, 0) > 0"]

    if @min_price.positive?
      min_cents = @min_price * 100
      sale_conditions << "valor_venda_cents >= #{min_cents}"
      rent_conditions << "valor_locacao_cents >= #{min_cents}"
    end

    if @max_price.positive?
      max_cents = @max_price * 100
      sale_conditions << "valor_venda_cents <= #{max_cents}"
      rent_conditions << "valor_locacao_cents <= #{max_cents}"
    end

    scope.where("(#{sale_conditions.join(' AND ')}) OR (#{rent_conditions.join(' AND ')})")
  end

  def apply_integer_range_filter(scope, column_name, min_value, max_value)
    column = ActiveRecord::Base.connection.quote_column_name(column_name.to_s)
    min = min_value.to_i if min_value.present?
    max = max_value.to_i if max_value.present?

    scope = scope.where("COALESCE(habitations.#{column}, 0) >= ?", min) if min.to_i.positive?
    scope = scope.where("COALESCE(habitations.#{column}, 0) <= ?", max) if max.to_i.positive?
    scope
  end

  def parse_date_param(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def apply_amenity_filter(scope, amenity)
    Habitations::AmenityFilter.call(scope, amenity)
  end

  def normalized_amenity_filter_options(values)
    normalize_amenity_filter_values(values)
      .sort_by { |name| AttributeOptions::HabitationFeatureNormalizer.key(name) }
  end

  def normalize_amenity_filter_values(values)
    Array(values)
      .flatten
      .filter_map { |value| AttributeOptions::HabitationFeatureNormalizer.label(value, category: "infrastructure") }
      .index_by { |value| AttributeOptions::HabitationFeatureNormalizer.key(value) }
      .values
  end

  def apply_front_sea_filter(scope)
    Habitations::AmenityFilter.call(scope, "Frente mar")
  end

  def apply_catalog_text_feature_filter(scope, term, boolean_column: nil)
    fragments = []
    fragments << "habitations.#{ActiveRecord::Base.connection.quote_column_name(boolean_column)} IS TRUE" if boolean_column.present?
    fragments << "(jsonb_typeof(habitations.caracteristicas) = 'array' AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(habitations.caracteristicas) value WHERE unaccent(value) ILIKE unaccent(:term_pattern)))"
    fragments << "(jsonb_typeof(habitations.caracteristicas) = 'object' AND EXISTS (SELECT 1 FROM jsonb_each_text(habitations.caracteristicas) kv WHERE unaccent(kv.key) ILIKE unaccent(:term_pattern) OR unaccent(kv.value) ILIKE unaccent(:term_pattern)))"
    fragments << "EXISTS (SELECT 1 FROM unnest((#{Habitation::SearchScopes::UNIQUE_FEATURES_ARRAY_SQL})) AS feature WHERE unaccent(feature) ILIKE unaccent(:term_pattern))"

    scope.where(fragments.join(" OR "), term_pattern: "%#{term}%")
  end

  def setup_paginated_report(scope)
    per_page = REPORT_PAGE_SIZE.fetch(@report_type, 27)
    total_entries = scope.count
    raw_pages = (total_entries.to_f / per_page).ceil

    @report_total_entries = total_entries
    @report_total_pages = [[raw_pages, 1].max, REPORT_MAX_PAGES].min
    @report_limited_to_max_pages = raw_pages > REPORT_MAX_PAGES

    requested_page = params[:page].to_i
    @report_page = requested_page.positive? ? requested_page : 1
    @report_page = @report_total_pages if @report_page > @report_total_pages

    offset = (@report_page - 1) * per_page
    @habitations = scope.offset(offset).limit(per_page)
    @report_pages_data = [@habitations.to_a]
  end

  def setup_full_report(scope)
    per_page = REPORT_PAGE_SIZE.fetch(@report_type, 27)
    raw_total_entries = scope.count
    max_entries = per_page * REPORT_MAX_PAGES
    effective_total_entries = [raw_total_entries, max_entries].min

    rows = scope.limit(max_entries).to_a
    @habitations = rows
    @report_pages_data = rows.each_slice(per_page).to_a.presence || [[]]

    @report_total_entries = effective_total_entries
    @report_total_pages = @report_pages_data.size
    @report_page = 1
    @report_limited_to_max_pages = raw_total_entries > max_entries
  end

  def setup_single_habitation_sheet_report(scope)
    habitation = scope.to_a.last
    records = [habitation].compact

    @habitations = records
    @report_pages_data = [records]
    @report_total_entries = records.size
    @report_total_pages = 1
    @report_page = 1
    @report_limited_to_max_pages = false
  end

  def full_print_mode?
    params[:full_print].to_s != "0"
  end

  def single_habitation_sheet_report?
    %w[visit_sheet capture_sheet_commercial capture_sheet_residential capture_sheet_land].include?(@report_type)
  end

  def habitation_params
    normalize_rental_guarantee_method_param!
    permitted = params.require(:habitation).permit(*permitted_habitation_fields)
    responsible_attributes = permitted.slice(:admin_user_id, :broker_assignments_attributes)
    normalize_registration_profile_selection!(permitted)
    strip_blank_photo_uploads!(permitted)
    normalize_blank_address_list_values!(permitted)

    # Filtro por perfil (allowlist): já derruba tudo que a config trava, tornando
    # o antigo deny-list (broker_protected_habitation_param_keys) redundante.
    permitted = Habitations::BrokerEditPolicy.filter(permitted, habitation: @habitation, admin_user: current_admin_user) if broker_restricted_habitation_edit?
    permitted.merge!(responsible_attributes) if can_manage_habitation_responsibles?

    unless can_view_proprietor_data?(@habitation)
      proprietor_locked_fields = %i[
        proprietario proprietario_codigo proprietario_email proprietario_celular
        proprietario_telefone_comercial proprietario_telefone_residencial proprietor_id
      ]
      proprietor_locked_fields.each { |field| permitted.delete(field) }
    end

    permitted.delete(:intake_status) unless @habitation&.broker_intake? && can_manage_intake_status?(@habitation)
    permitted.delete(:foto_classificacao) unless can_manage_habitation_signal_flags?

    permitted
  end

  def strip_blank_photo_uploads!(permitted)
    Habitations::MediaUpdater.strip_blank_photo_uploads!(permitted)
  end

  def normalize_blank_address_list_values!(permitted)
    address_attributes = permitted[:address_attributes]
    return unless address_attributes&.key?(:imediacoes)

    address_attributes[:imediacoes] = Array(address_attributes[:imediacoes])
      .map { |value| value.to_s.strip }
      .reject(&:blank?)
  end

  def extract_photo_uploads!(permitted)
    habitation_media_updater.extract_photo_uploads!(permitted)
  end

  def extract_document_uploads!(permitted)
    habitation_media_updater.extract_document_uploads!(permitted)
  end

  def attach_new_photos(habitation, uploads, apply_watermark: false)
    habitation_media_updater(habitation).attach_new_photos(uploads, apply_watermark: apply_watermark)
  end

  def attach_new_documents(habitation, document_uploads)
    habitation_media_updater(habitation).attach_new_documents(document_uploads)
  end

  def apply_picture_removals_to_memory(habitation)
    habitation_media_updater(habitation).apply_picture_removals_to_memory
  end

  def apply_saved_photo_removals(habitation)
    habitation_media_updater(habitation).apply_saved_photo_removals
  end

  def selected_photo_attachment_ids_for_removal
    habitation_media_updater.selected_photo_attachment_ids_for_removal
  end

  def selected_picture_indices_for_removal
    habitation_media_updater.selected_picture_indices_for_removal
  end

  def preload_operational_hub_associations
    ActiveRecord::Associations::Preloader.new(
      records: [@habitation],
      associations: [:admin_user, :photos_attachments, :fichas_cadastro_attachments, :autorizacoes_venda_attachments]
    ).call
  end

  def operational_hub_logs
    @operational_hub_logs ||= @habitation.habitation_audit_logs.includes(:admin_user).recent.limit(80)
  end

  def filter_empreendimento_options
    Admin::HabitationDevelopmentFilterOptions.call(current_tenant.habitations)
  end

  def record_habitation_created(habitation)
    Habitations::AuditChangeRecorder.new(
      habitation,
      actor: current_admin_user,
      request: request,
      source: habitation_audit_source(habitation)
    ).record_create!
  end

  def record_habitation_updated(habitation, before_snapshot: nil)
    Habitations::AuditChangeRecorder.new(
      habitation,
      actor: current_admin_user,
      request: request,
      source: habitation_audit_source(habitation),
      before_snapshot: before_snapshot,
      ignored_fields: Habitations::AuditChangeRecorder::ADMIN_NOISE_FIELDS
    ).record_update!
  end

  def record_habitation_destroyed(habitation)
    Habitations::AuditChangeRecorder.new(
      habitation,
      actor: current_admin_user,
      request: request,
      source: habitation_audit_source(habitation),
      before_snapshot: Habitations::AuditChangeRecorder.snapshot_for(habitation)
    ).record_destroy!
  end

  def release_habitation_destroy_references(habitation)
    destroy_habitation_child_records(habitation)
    nullify_habitation_history_references(habitation)
  end

  def destroy_habitation_child_records(habitation)
    [
      AiPropertyShareItem,
      HabitationPhotoShare,
      LeadPropertyInterest
    ].each do |model|
      model.where(habitation_id: habitation.id).destroy_all
    end
  end

  def nullify_habitation_history_references(habitation)
    [
      [AiPropertySearchHistory, :selected_habitation_id],
      [AiPropertyShareAuditEvent, :habitation_id],
      [Appointment, :habitation_id],
      [ClientInteraction, :habitation_id],
      [ClientPropertyInterest, :habitation_id],
      [CrmAppointment, :habitation_id],
      [OperationalUserEvent, :habitation_id],
      [PortalIntegrationEvent, :habitation_id],
      [PortalListingState, :habitation_id],
      [Proposal, :habitation_id],
      [PublicNavigationEvent, :habitation_id],
      [SeoConversionEvent, :habitation_id],
      [VistaFileAsset, :habitation_id]
    ].each do |model, column|
      nullify_habitation_reference(model, column, habitation.id)
    end
  end

  def nullify_habitation_reference(model, column, habitation_id)
    attributes = { column => nil }
    attributes[:updated_at] = Time.current if model.column_names.include?("updated_at")
    model.where(column => habitation_id).update_all(attributes)
  end

  def record_habitation_attachment_removed(habitation, association:, attachment_payload:)
    Habitations::AuditChangeRecorder.new(
      habitation,
      actor: current_admin_user,
      request: request,
      source: habitation_audit_source(habitation)
    ).record_attachment_removed!(
      association: association,
      attachment_payload: attachment_payload
    )
  end

  def record_owner_contact_confirmed(habitation, confirmed_at:)
    HabitationAuditLog.create!(
      habitation: habitation,
      admin_user: current_admin_user,
      action: "owner_contact_confirmed",
      source: habitation_audit_source(habitation),
      changed_fields: ["owner_contact_confirmation", "data_atualizacao_crm"],
      changeset: {
        "owner_contact_confirmation" => {
          before: nil,
          after: "Falei com proprietário e não houve alteração"
        },
        "data_atualizacao_crm" => {
          before: nil,
          after: confirmed_at
        }
      },
      metadata: {
        owner_contact_confirmed: true,
        confirmed_at: confirmed_at.iso8601
      },
      ip: request.remote_ip,
      user_agent: request.user_agent.to_s.first(255)
    )
  end

  def record_rental_short_cycle_alert(habitation, payload)
    HabitationAuditLog.create!(
      habitation: habitation,
      admin_user: current_admin_user,
      action: "rental_short_cycle_alert",
      source: habitation_audit_source(habitation),
      changed_fields: ["status", "rental_short_cycle_alert"],
      changeset: {
        "status" => {
          before: payload[:previous_status],
          after: payload[:new_status]
        },
        "rental_short_cycle_alert" => {
          before: nil,
          after: "Locação encerrada com #{payload[:days_in_market]} dias em pauta"
        }
      },
      metadata: payload,
      ip: request.remote_ip,
      user_agent: request.user_agent.to_s.first(255)
    )
  end

  def rental_short_cycle_alert_payload(habitation, before_snapshot:)
    before_attributes = before_snapshot.to_h.fetch("attributes", {})
    previous_status = before_attributes["status"].to_s
    new_status = habitation.status.to_s
    return nil if previous_status == new_status
    return nil unless rental_before_status_change?(before_attributes)
    return nil unless new_status_for_rental_short_cycle_alert?(habitation)

    entered_at = rental_market_entry_at(habitation, before_attributes)
    return nil unless entered_at.present?

    days_in_market = ((Time.current - entered_at) / 1.day).floor
    return nil unless days_in_market >= 0 && days_in_market < 30

    {
      previous_status: previous_status.presence,
      new_status: new_status,
      days_in_market: days_in_market,
      market_entry_at: entered_at.iso8601,
      alert_reason: "Locação saiu de pauta em menos de 30 dias"
    }
  end

  def rental_before_status_change?(attributes)
    return true if attributes["valor_locacao_cents"].to_i.positive?
    return true if attributes["intake_modalidade"].to_s.in?(%w[locacao_anual locacao_diaria ambos])

    attributes["status"].to_s.match?(/aluguel|loca/i)
  end

  def new_status_for_rental_short_cycle_alert?(habitation)
    normalized_status = Habitation.normalize_status(habitation.status).to_s.parameterize
    normalized_status.include?("alugado") || normalized_status.include?("suspenso")
  end

  def rental_market_entry_at(habitation, attributes)
    raw_value = attributes["data_cadastro_crm"].presence || habitation.data_cadastro_crm || habitation.created_at
    raw_value.is_a?(String) ? Time.zone.parse(raw_value) : raw_value
  rescue ArgumentError, TypeError
    habitation.created_at
  end

  def bulk_habitation_audit_changesets(ids, updates)
    audit_fields = updates.keys.map(&:to_s) & Habitations::AuditChangeRecorder.audited_habitation_fields
    audit_fields -= %w[updated_at]
    return {} if audit_fields.blank?

    current_tenant.habitations.where(id: ids).pluck(:id, *audit_fields).each_with_object({}) do |row, result|
      habitation_id = row.first
      changeset = {}

      audit_fields.each_with_index do |field, index|
        before_value = row[index + 1]
        after_value = updates.key?(field.to_sym) ? updates[field.to_sym] : updates[field]
        changeset[field] = { before: before_value, after: after_value }
      end

      result[habitation_id] = changeset
    end
  end

  def record_bulk_habitation_updates(changesets_by_id, action_type:, channels:)
    return if changesets_by_id.blank?

    current_tenant.habitations.where(id: changesets_by_id.keys).find_each do |habitation|
      Habitations::AuditChangeRecorder.new(
        habitation,
        actor: current_admin_user,
        request: request,
        source: habitation_audit_source(habitation)
      ).record_bulk_update!(
        changesets_by_id[habitation.id],
        metadata: {
          action_type: action_type,
          channels: channels
        }
      )
    end
  end

  def habitation_audit_source(habitation)
    habitation&.broker_intake? ? "captacao" : "admin"
  end

  def permitted_habitation_fields
    [
      :slug, :registration_profile, :categoria, :status, :situacao, :tipo, :codigo_empreendimento,
      :nome_empreendimento,
      :dormitorios_qtd, :suites_qtd, :salas_qtd, :varandas_qtd, :banheiros_qtd, :hidromassagem_qtd, :vagas_qtd, :elevadores_qtd, 
      :area_privativa_m2, :area_total_m2, :area_terreno_m2, :area_util_m2, 
      :valor_venda_formatted, :valor_locacao_formatted, :valor_alugado_terceiros_formatted, :valor_vendido_terceiros_formatted,
      :valor_condominio_formatted, :valor_iptu_formatted, :valor_por_m2_formatted,
      :valor_locacao_anterior_formatted, :valor_aceito_permuta_formatted, :permuta_valor_formatted,
      :permuta_veiculo_valor_formatted, :permuta_outros_valor_formatted, :saldo_devedor_formatted,
      :valor_comissao_formatted, :valor_livre_proprietario_formatted,
      :descricao_web, :descricao_interna, :titulo_anuncio, :observacoes, 
      :condicoes_negociacao, :observacoes_visitas, :motivo_suspensao,
      :corretor_nome, :corretor_telefone, :corretor_email, :proprietario_codigo,
      :proprietario, :proprietario_celular, :proprietario_telefone_comercial,
      :proprietario_telefone_residencial, :proprietario_email, :proprietario_cidade,
      :exibir_no_site_flag, :destaque_web_flag, :lancamento_flag, :aceita_permuta_flag,
      :aceita_permuta_veiculo_flag, :aceita_permuta_imovel_flag, :aceita_permuta_outros_flag,
      :aceita_financiamento_flag, :aceita_parcelamento_flag, :mobiliado_flag, :data_entrega,
      :meta_title, :meta_description, :meta_keywords, :public_rating_value, :public_rating_count, :public_rating_source,
      :piscina_flag, :lavabo_flag, :varanda_gourmet_flag, :bloco, :lote,
      :banheiro_social_qtd, :decorado_flag, :aptos_andar, :aptos_edificio,
      :garden_flag, :quadra_mar_flag, :sem_mobilia_flag, 
      :valor_venda_anterior_cents, :valor_venda_anterior_formatted, :valor_total_aluguel_cents, :valor_promocional_formatted, 
      :proprietario, :inscricao_imobiliaria, :descricao_empreendimento,
      :categoria_grupo, :tour_virtual,
      :public_map_display_mode, :public_street_view_mode,
      :constructor_id, :proprietor_id, :admin_user_id,
      :terceira_avenida_flag, :arriba_flag, :avenida_brasil_flag, :bairro_fazenda_itajai_flag, 
      :balneario_picarras_flag, :barra_flag, :barra_norte_flag, :barra_sul_flag, 
      :cabecudas_flag, :camboriu_flag, :centro_flag, :estaleirinho_flag, 
      :frente_mar_avenida_atlantica_flag, :itajai_flag, :itapema_flag, :nacoes_flag, 
      :pioneiros_flag, :praia_brava_flag, :praia_dos_amores_flag, :vista_frente_mar_flag, 
      :festival_flag, :exibir_no_site_portal_flag, :tem_placa_flag, :imovel_dwv,
      :publicar_imovelweb_2, :publicar_netimoveis_2, :publicar_lais_ai, :publicar_loft,
      :publicar_chaves_na_mao, :publicar_casa_mineira, :publicar_imovelweb, :publicar_viva_real_vrsync,
      :destaque_chaves_na_mao, :periodo_locacao_chaves_na_mao,
      :modelo_casa_mineira,
      :tipo_publicacao_viva_real, :divulgar_endereco_viva_real,
      :tipo_publicacao_imovelweb, :mostrar_mapa_imovelweb,
      :tipo_publicacao_imovelweb_2, :mostrar_mapa_imovelweb_2,
      :exclusivo_flag, :ocupacao_status, :estado_conservacao,
      :andar, :ano_construcao, :demi_suites_qtd, :numero_box, :tipo_vaga,
      :dimensoes_terreno, :topografia, :foto_classificacao, :podcast_url,
      :matricula_imovel, :zona, :numero_prestacoes, :responsavel_reserva, :zelador_nome, :zelador_telefone, :regiao_foco,
      :construtora, :tipo_fachada, :andares_qtd, :perfil_construcao, :face,
      :tipo_veiculo_aceito_permuta, :ano_minimo_veiculo_aceito_permuta,
      :permuta_localizacao, :permuta_dormitorios_qtd, :permuta_suites_qtd, :permuta_garagens_qtd,
      :permuta_outros_descricao,
      :agenciador, :captador_commission_percentage, :broker_commission_percentage,
      :rental_management_answer,
      :rental_management_flag, :home_corporate_flag, :home_corporate_position,
      :key_location, :key_location_notes, :senha_portaria, :senha_imovel, :ordered_photo_ids, :ordered_picture_indices, :site_hidden_photo_ids, :site_hidden_picture_urls, :intake_status,
      :use_development_photos_flag,
      rental_guarantee_method: [],
      videos: [], plantas: [], fotos_empreendimento: [], photos: [],
      fichas_cadastro: [], autorizacoes_venda: [],
      meta_keywords: [],
      caracteristicas: [], infra_estrutura: [], caracteristica_unica: [],
      broker_assignments_attributes: [:id, :admin_user_id, :role, :commission_type, :commission_value, :observations, :_destroy],
      address_attributes: [:id, :tipo_endereco, :logradouro, :numero, :complemento, :bairro, :bairro_comercial, :cidade, :uf, :cep, :pais, :latitude, :longitude, :_destroy, { imediacoes: [] }]
    ]
  end

  def apply_photo_watermark_requested?
    habitation_media_updater.apply_photo_watermark_requested?
  end

  def habitation_media_updater(habitation = @habitation)
    Habitations::MediaUpdater.new(
      habitation: habitation,
      params: params,
      actor: current_admin_user,
      request: request,
      property_setting: @property_setting
    )
  end

  def load_property_setting
    @property_setting = PropertySetting.instance
  end

  def review_required_checks_for(habitation)
    PropertyReviewPolicyResolver
      .for_habitation(habitation, property_setting: @property_setting)
      .required_checks
  end

  def snapshot_review_policy!(habitation)
    return unless habitation.has_attribute?(:intake_review_policy_snapshot)

    result = PropertyReviewPolicyResolver.for_habitation(habitation, property_setting: @property_setting)
    rule = result.policy || @property_setting
    habitation.assign_attributes(
      intake_review_policy_version: review_policy_version_for(rule),
      intake_review_policy_snapshot: {
        source: result.source.to_s,
        registration_type: result.registration_type,
        category: result.category,
        modality: result.modality,
        policy_id: result.policy&.id,
        required_broker_intake_checks: result.required_checks,
        returnable_intake_edit_sections: result.returnable_sections,
        broker_capture_layer_enabled: rule.broker_capture_layer_enabled
      }
    )
  end

  def review_policy_version_for(rule)
    return rule.version if rule.respond_to?(:version)
    return rule.review_policy_version if rule.respond_to?(:review_policy_version)

    nil
  end

  def broker_protected_habitation_param_keys
    %w[
      admin_user_id
      broker_assignments_attributes
      descricao_interna
      public_map_display_mode
      public_street_view_mode
      proprietario
      proprietario_codigo
      proprietario_celular
      proprietario_telefone_comercial
      proprietario_telefone_residencial
      proprietor_id
      fichas_cadastro
      autorizacoes_venda
    ]
  end

  def can_manage_habitation_signal_flags?
    tenant_owner? || owns_all_resource?(:imoveis) || can_review_captacao?(@habitation)
  end

  # Exclusão de imóvel é destrutiva e fica restrita ao dono/admin da conta.
  # Perfis operacionais com :delete legado continuam bloqueados.
  def can_destroy_habitation?(_habitation = @habitation)
    current_admin_user&.tenant_owner?
  end

  def can_duplicate_habitation?(habitation = @habitation)
    return false unless habitation
    return false unless can?(:create, :imoveis)
    return false unless can_edit_habitation?(habitation)

    property_accessible?(habitation)
  end

  def can_bulk_publish_habitations?
    tenant_owner? || (can?(:edit, :imoveis) && owns_all_resource?(:imoveis))
  end

  def can_manage_habitation_responsibles?(_habitation = @habitation)
    return false unless current_admin_user
    return true if admin_or_administrative_user?

    team_manager = current_admin_user.can_view_team?(:imoveis) || current_admin_user.can_view_team?(:captacoes)
    team_manager && (can?(:edit, :imoveis) || can?(:review, :captacoes))
  end

  # Card #1 (Fase 4): "edita os campos protegidos livremente" = perfil sem NENHUMA
  # trava (dono do tenant, ou full-access semeado com locked_fields: []). Usado
  # como gate GROSSO nos readonly/disabled de Endereço/Proprietário/Empreendimento.
  # Para trava por campo específico, ver habitation_field_editable? (helper) —
  # perfil PARCIALMENTE travado trava esses blocos de forma conservadora.
  def can_edit_protected_habitation_fields?
    Habitations::FieldLockPolicy.for(current_admin_user).locked_keys.empty?
  end

  # Card #1 (Fase 4): só o dono edita tudo; todo o resto passa pela config do
  # perfil (FieldLockPolicy). Para full-access a config foi semeada vazia, então
  # nada é travado — o filtro roda mas libera tudo.
  def broker_restricted_habitation_edit?
    current_admin_user.present? && !current_admin_user.tenant_owner?
  end

  def broker_habitation_allowed_fields
    Habitations::FieldLockPolicy.for(current_admin_user).allowed_frontend_fields
  end

  def broker_habitation_allowed_actions
    Habitations::FieldLockPolicy.for(current_admin_user).allowed_action_keys
  end

  def property_belongs_to_current_user?(habitation)
    return false unless current_admin_user
    return true if habitation.admin_user_id == current_admin_user.id
    return true if habitation.broker_assignments.loaded? ? habitation.broker_assignments.any? { |assignment| assignment.admin_user_id == current_admin_user.id } : habitation.broker_assignments.exists?(admin_user_id: current_admin_user.id)

    broker_name = current_admin_user.name.to_s.strip
    broker_name.present? && habitation.corretor_nome.to_s.downcase.include?(broker_name.downcase)
  end

  def property_captured_by_current_user?(habitation)
    return false unless current_admin_user
    return true if habitation.admin_user_id == current_admin_user.id
    if habitation.broker_assignments.loaded?
      return true if habitation.broker_assignments.any? { |assignment| assignment.admin_user_id == current_admin_user.id && assignment.role == "captador" }
    elsif habitation.broker_assignments.exists?(admin_user_id: current_admin_user.id, role: HabitationBrokerAssignment.roles.fetch("captador"))
      return true
    end

    broker_name = current_admin_user.name.to_s.strip
    broker_name.present? && habitation.corretor_nome.to_s.downcase.include?(broker_name.downcase)
  end

  def can_filter_by_proprietor?
    can_export_proprietor_data?
  end

  def can_filter_by_broker?
    tenant_owner? || can?(:view, :imoveis)
  end

  def can_view_habitation_administrative_filters?
    return true if system_admin? || tenant_owner?

    profile = current_admin_user&.access_profile
    root_profile = profile&.root_vertical_profile || current_admin_user&.vertical_profile
    root_profile&.administrativo? || root_profile&.gerente?
  end

  def broker_catalog_user?
    return false if system_admin? || tenant_owner?

    profile = current_admin_user&.access_profile
    root_profile = profile&.root_vertical_profile || current_admin_user&.vertical_profile
    root_profile&.agent?
  end

  def can_export_proprietor_data?
    can_access_sensitive_habitation_data?
  end

  def habitation_visible_admin_users
    # Memoizado: era reconstruído (e reexecutava accessible_owner_ids) a cada
    # chamada — usado em @brokers e por corretor no form.
    @habitation_visible_admin_users ||= begin
      ids = accessible_owner_ids(:imoveis)
      scope = current_tenant.admin_users.active
      ids.nil? ? scope : scope.where(id: ids)
    end
  end

  def catalog_filter_admin_users
    # O catálogo operacional pode ser filtrado por colegas da mesma conta.
    # Edição/atribuição de responsáveis continua usando habitation_visible_admin_users.
    current_tenant.admin_users.active
  end

  def catalog_filter_admin_user_id(value)
    return nil if value.blank?

    id = value.to_i
    return nil unless id.positive?

    catalog_filter_admin_users.exists?(id: id) ? id.to_s : nil
  end

  def catalog_filter_admin_user_ids(value)
    ids = Array(value)
      .flatten
      .flat_map { |item| item.to_s.split(",") }
      .filter_map { |item| Integer(item, exception: false) }
      .select(&:positive?)
      .uniq

    ids.blank? ? [] : catalog_filter_admin_users.where(id: ids).pluck(:id)
  end

  def filter_values(value, except: nil)
    normalized_except = I18n.transliterate(except.to_s).downcase if except.present?

    Array(value)
      .flatten
      .flat_map { |item| item.to_s.split(",") }
      .map(&:squish)
      .reject(&:blank?)
      .reject { |item| normalized_except.present? && I18n.transliterate(item).downcase == normalized_except }
      .uniq
  end

  def visible_habitation_admin_user_id(value)
    return nil if value.blank?

    id = value.to_i
    return nil unless id.positive?

    habitation_visible_admin_users.exists?(id: id) ? id.to_s : nil
  end

  # Dados sensíveis da conta INTEIRA: exige escopo total. Revisor com escopo de
  # equipe acessa os dados da própria hierarquia pelos caminhos de gestor
  # (manager_can_view_proprietor_data?), nunca por este atalho global.
  def can_access_sensitive_habitation_data?
    tenant_owner? || owns_all_resource?(:imoveis) || (can?(:review, :captacoes) && owns_all_resource?(:captacoes))
  end

  def can_sync_habitation_proprietor?
    return true if can_access_sensitive_habitation_data?
    return false unless current_admin_user
    return false unless can?(:edit, :imoveis)

    !Habitations::FieldLockPolicy.for(current_admin_user).field_locked?("proprietor_id")
  end

  # manager_team_user_ids / manager_allowed_acting_types vivem no BaseController.
  def manager_can_view_proprietor_data?(habitation)
    return false unless habitation_matches_current_user_acting_type?(habitation, total_access: false)

    team_ids = manager_team_user_ids
    return false if team_ids.blank?
    return true if habitation.admin_user_id.in?(team_ids)
    return true if habitation.broker_assignments.exists?(admin_user_id: team_ids)

    false
  end

  def habitation_matches_current_user_acting_type?(habitation, total_access: true)
    return true if habitation.blank? || current_admin_user.blank?
    return true if total_access && (tenant_owner? || owns_all_resource?(:imoveis))
    return true if current_admin_user.both?

    sale_property = sale_area_habitation?(habitation)
    rental_property = rental_area_habitation?(habitation)
    return true unless sale_property || rental_property

    case current_admin_user.acting_type
    when "sales"
      sale_property
    when "rentals"
      rental_property
    else
      true
    end
  end

  def sale_area_habitation?(habitation)
    status = habitation.status.to_s.parameterize
    habitation.valor_venda_cents.to_i.positive? || status.match?(/venda|vendido/)
  end

  def rental_area_habitation?(habitation)
    status = habitation.status.to_s.parameterize
    habitation.valor_locacao_cents.to_i.positive? || status.match?(/aluguel|locacao|diaria|alugado/)
  end

  def restrict_pending_review_to_manager_team(scope)
    team_ids = manager_team_user_ids
    return scope.none if team_ids.blank?

    scope.where(
      "habitations.admin_user_id IN (:ids) OR EXISTS (
        SELECT 1
        FROM habitation_broker_assignments
        WHERE habitation_broker_assignments.habitation_id = habitations.id
          AND habitation_broker_assignments.admin_user_id IN (:ids)
      )",
      ids: team_ids
    )
  end

  def assign_proprietor_from_legacy_fields(habitation)
    Habitations::ProprietorLinker.new(habitation).call
  end
end
