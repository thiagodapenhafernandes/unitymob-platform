module Admin::HabitationsHelper
  BOOLEAN_TYPE = ActiveModel::Type::Boolean.new

  PUBLICATION_CHANNEL_LABELS = {
    exibir_no_site_flag: "Site",
    publicar_zapimoveis: "Zapimoveis",
    publicar_viva_real_vrsync: "Viva Real",
    publicar_imovelweb: "Imovelweb",
    publicar_imovelweb_2: "Imovelweb 2",
    publicar_chaves_na_mao: "Chaves na Mão",
    publicar_casa_mineira: "Casa Mineira",
    publicar_lais_ai: "Lais AI",
    publicar_netimoveis_2: "Netimoveis 2",
    publicar_loft: "Loft"
  }.freeze

  def admin_habitation_internal_path(habitation, return_to: nil)
    route_param = admin_habitation_route_param(habitation)
    path_params = admin_habitation_flat_return_params(return_to)

    if admin_can_edit_habitation?(habitation)
      admin_habitation_path_with_query(edit_admin_habitation_path(route_param), path_params)
    else
      admin_habitation_path_with_query(admin_habitation_path(route_param), path_params)
    end
  end

  def admin_habitation_route_param(habitation)
    habitation.respond_to?(:id) ? habitation.id : habitation
  end

  def admin_habitation_flat_return_params(return_to)
    path = return_to.to_s.strip
    return {} if path.blank?

    uri = URI.parse(path)
    return {} if uri.scheme.present? || uri.host.present? || uri.path.blank?

    query_params = Rack::Utils.parse_nested_query(uri.query.to_s)
    query_params = query_params.merge("back_anchor" => uri.fragment) if uri.fragment.present?
    query_params.merge("return_to" => uri.path)
  rescue URI::InvalidURIError
    {}
  end

  def admin_habitation_path_with_query(path, query_params)
    normalized_params = query_params.to_h.stringify_keys.compact_blank
    return path if normalized_params.blank?

    return_to = normalized_params.delete("return_to")
    query_parts = []
    query_parts << "return_to=#{return_to}" if return_to.present?
    query_parts << Rack::Utils.build_nested_query(normalized_params) if normalized_params.present?

    path_without_fragment, fragment = path.split("#", 2)
    separator = path_without_fragment.include?("?") ? "&" : "?"
    fragment_suffix = fragment.present? ? "##{fragment}" : ""

    "#{path_without_fragment}#{separator}#{query_parts.join("&")}#{fragment_suffix}"
  end

  def admin_habitation_internal_action_label(habitation)
    admin_can_edit_habitation?(habitation) ? "Editar imóvel" : "Abrir cadastro"
  end

  def admin_habitation_catalog_card_path(habitation, ownership_scope:, intake_review:, return_to: nil)
    admin_habitation_internal_path(habitation, return_to: return_to)
  end

  def admin_habitation_catalog_action_label(habitation, ownership_scope:, intake_review:)
    admin_habitation_internal_action_label(habitation)
  end

  def admin_habitation_publication_channels(habitation)
    publication_channel_columns.filter_map do |column|
      next unless habitation.respond_to?(column) && BOOLEAN_TYPE.cast(habitation.public_send(column))

      PUBLICATION_CHANNEL_LABELS[column] || publication_channel_label_for(column)
    end
  end

  def admin_can_edit_habitation?(habitation)
    return false unless current_admin_user && habitation

    cache_key = habitation.id || habitation.object_id
    @admin_habitation_edit_permissions ||= {}
    return @admin_habitation_edit_permissions[cache_key] if @admin_habitation_edit_permissions.key?(cache_key)

    @admin_habitation_edit_permissions[cache_key] =
      current_admin_user.owns_all?(:imoveis) ||
      habitation.admin_user_id == current_admin_user.id ||
      habitation_assigned_to_current_user?(habitation) ||
      habitation_matches_current_broker_name?(habitation)
  end

  def admin_can_manage_habitation_media?(habitation)
    return false unless current_admin_user && habitation
    return false unless can?(:media, :imoveis) || can?(:manage, :imoveis)
    return true if current_admin_user.owns_all?(:imoveis)
    return true if admin_can_edit_habitation?(habitation)

    admin_habitation_catalog_media_visible?(habitation)
  end

  def habitation_assigned_to_current_user?(habitation)
    if habitation.broker_assignments.loaded?
      habitation.broker_assignments.any? { |assignment| assignment.admin_user_id == current_admin_user.id }
    else
      habitation.broker_assignments.exists?(admin_user_id: current_admin_user.id)
    end
  end

  def habitation_matches_current_broker_name?(habitation)
    broker_name = current_admin_user.name.to_s.strip.downcase
    broker_name.present? && habitation.corretor_nome.to_s.downcase.include?(broker_name)
  end

  private

  def admin_habitation_catalog_media_visible?(habitation)
    return false if habitation.respond_to?(:tenant_id) && current_tenant.present? && habitation.tenant_id != current_tenant.id
    return true unless habitation.respond_to?(:broker_intake?) && habitation.broker_intake?

    Habitation::CATALOG_VISIBLE_INTAKE_STATUSES.include?(habitation.intake_status)
  end

  def publication_channel_columns
    return @publication_channel_columns if defined?(@publication_channel_columns)

    portal_columns = Habitation::PORTAL_PUBLICATION_FIELDS.values
    dynamic_publication_columns = Habitation.column_names.grep(/\Apublicar_/).map(&:to_sym)

    @publication_channel_columns = ([:exibir_no_site_flag] + portal_columns + dynamic_publication_columns).uniq
  end

  def publication_channel_label_for(column)
    column.to_s.sub(/\Apublicar_/, "").humanize
  end
end
