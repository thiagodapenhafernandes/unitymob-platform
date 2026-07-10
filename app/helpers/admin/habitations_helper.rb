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

  def admin_habitation_pending_intake_status(habitation, intake_review:)
    return unless intake_review == "pending"
    return unless habitation.broker_intake?
    return unless habitation.intake_status.in?(Habitation::PENDING_WORKFLOW_INTAKE_STATUSES)

    {
      label: habitation.intake_status_label,
      broker_action: habitation.intake_status.in?(%w[draft admin_approved returned_to_broker])
    }
  end

  def admin_habitation_catalog_title(habitation)
    parts = [
      admin_habitation_catalog_neighborhood(habitation),
      admin_habitation_catalog_development_name(habitation),
      habitation.display_title
    ].compact_blank

    deduplicate_catalog_title_parts(parts).join(" · ")
  end

  def admin_habitation_catalog_card_title(habitation)
    parts = [
      admin_habitation_catalog_neighborhood(habitation),
      admin_habitation_catalog_development_name(habitation)
    ].compact_blank

    compact_title = deduplicate_catalog_title_parts(parts).join(" · ")
    compact_title.presence || habitation.display_title
  end

  def admin_filter_choice_label(choices, selected_value)
    selected_value = selected_value.to_s
    return if selected_value.blank?

    Array(choices).each do |choice|
      label, value = choice.is_a?(Array) ? choice : [choice, choice]
      return label if value.to_s == selected_value
    end

    selected_value
  end

  def admin_habitation_development_filter_label(selected_value)
    label = admin_filter_choice_label(@filter_empreendimentos, selected_value)
    return label if label.present? && label != selected_value.to_s

    parsed = Admin::HabitationDevelopmentFilterOptions.parse(selected_value)
    if parsed[:type] == :standalone
      return parsed[:value]
    end

    lookup_value = parsed[:type] == :development ? parsed[:value] : selected_value
    current_tenant.habitations
      .empreendimentos
      .where(codigo: lookup_value.to_s)
      .pick(:nome_empreendimento)
      .presence || parsed[:value].presence || label || selected_value
  end

  def admin_habitation_address_unit_parts(habitation)
    return [] unless habitation

    parts = []
    complement = habitation.complemento.to_s.strip.presence

    if habitation.respond_to?(:condominium_house?) && habitation.condominium_house?
      parts << labeled_unit_value("Casa", complement)
      parts << labeled_unit_value("Lote", habitation.lote)
      parts << labeled_unit_value("Quadra", habitation.quadra)
    elsif habitation.respond_to?(:requires_unit_number?) && habitation.requires_unit_number?
      parts << labeled_unit_value("Apto.", complement)
    elsif habitation.respond_to?(:street_house?) && habitation.street_house?
      parts << labeled_unit_value("Casa", complement)
    elsif complement.present?
      parts << complement
    end

    parts.compact_blank
  end

  def admin_habitation_address_unit_label(habitation, separator: " · ")
    admin_habitation_address_unit_parts(habitation).join(separator)
  end

  def admin_habitation_publication_channels(habitation)
    publication_channel_columns.filter_map do |column|
      next unless habitation.respond_to?(column) && BOOLEAN_TYPE.cast(habitation.public_send(column))

      PUBLICATION_CHANNEL_LABELS[column] || publication_channel_label_for(column)
    end
  end

  def admin_habitation_editor_tab_missing_counts(habitation, property_setting: nil)
    checks = property_setting&.active_broker_capture_checks
    missing_items = habitation.intake_missing_requirements(required_checks: checks, require_owner_city: true)
    missing_items.each_with_object(Hash.new(0)) do |message, counts|
      counts[admin_habitation_editor_tab_for_requirement(message)] += 1
    end
  end

  def admin_habitation_editor_tab_validation_rules(habitation, property_setting: nil)
    checks = property_setting&.active_broker_capture_checks
    habitation.intake_missing_requirements(required_checks: checks, require_owner_city: true).filter_map do |message|
      rule = admin_habitation_editor_rule_for_requirement(message)
      next unless rule

      rule.merge(tab: admin_habitation_editor_tab_for_requirement(message), label: message)
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

  def admin_habitation_catalog_neighborhood(habitation)
    address = habitation.association(:address).loaded? ? habitation.address : nil

    address&.bairro_comercial.presence ||
      habitation.bairro_comercial.presence ||
      habitation.read_attribute(:bairro_comercial).presence ||
      address&.bairro.presence ||
      habitation.read_attribute(:bairro).presence ||
      habitation.bairro.presence
  end

  def admin_habitation_catalog_development_name(habitation)
    return habitation.nome_empreendimento if habitation.nome_empreendimento.present?
    return unless habitation.association(:empreendimento).loaded?

    habitation.empreendimento&.nome_empreendimento.presence ||
      habitation.empreendimento&.titulo_anuncio.presence
  end

  def deduplicate_catalog_title_parts(parts)
    parts.each_with_object([]) do |part, unique_parts|
      normalized_part = normalize_catalog_title_part(part)
      next if normalized_part.blank?
      next if unique_parts.any? { |existing| normalize_catalog_title_part(existing) == normalized_part }

      unique_parts << part
    end
  end

  def normalize_catalog_title_part(part)
    I18n.transliterate(part.to_s).squish.downcase
  end

  def admin_habitation_catalog_media_visible?(habitation)
    return false if habitation.respond_to?(:tenant_id) && current_tenant.present? && habitation.tenant_id != current_tenant.id
    return true unless habitation.respond_to?(:broker_intake?) && habitation.broker_intake?

    Habitation::CATALOG_VISIBLE_INTAKE_STATUSES.include?(habitation.intake_status)
  end

  def admin_habitation_editor_tab_for_requirement(message)
    case message.to_s
    when "Título do anúncio", "Título do anúncio coerente com a categoria", "Descrição do imóvel", "Mais características"
      :features
    when "Infraestrutura & Lazer"
      :infra
    when "Dados do proprietário", "Cidade do proprietário",
         "Financeiro e valores", "Administração da locação", "Meio de garantia locatícia",
         "Aceita permuta", "Quantidade de parcelas", "Chaves", "Dias de visita"
      :commercial
    when "Fotos ou agenda com fotógrafo", "Agenda com fotógrafo"
      :media
    when "Anexo da autorização do proprietário"
      :documents
    else
      :general
    end
  end

  def admin_habitation_editor_rule_for_requirement(message)
    case message.to_s
    when "Dados do proprietário"
      {
        mode: "groups_present",
        groups: [
          %w[habitation[proprietario] habitation[proprietor_id]],
          %w[habitation[proprietario_celular] habitation[proprietario_telefone_comercial] habitation[proprietario_telefone_residencial] habitation[proprietario_email]]
        ]
      }
    when "Cidade do proprietário"
      { mode: "any_present", names: %w[habitation[proprietario_cidade]] }
    when "Endereço e localização"
      {
        mode: "all_present",
        names: %w[
          habitation[address_attributes][cep]
          habitation[address_attributes][logradouro]
          habitation[address_attributes][bairro]
          habitation[address_attributes][cidade]
          habitation[address_attributes][uf]
        ]
      }
    when "Empreendimento"
      { mode: "any_present", names: %w[habitation[nome_empreendimento] habitation[codigo_empreendimento]] }
    when "Número da unidade"
      { mode: "any_present", names: %w[habitation[bloco]] }
    when "Complemento"
      { mode: "any_present", names: %w[habitation[complemento] habitation[address_attributes][complemento]] }
    when "Definições básicas"
      { mode: "all_present", names: %w[habitation[categoria] habitation[status]] }
    when "Título do anúncio", "Título do anúncio coerente com a categoria"
      { mode: "any_present", names: %w[habitation[titulo_anuncio]] }
    when "Descrição do imóvel"
      { mode: "any_present", names: %w[habitation[descricao_web]] }
    when "Área privativa"
      { mode: "positive_any", names: %w[habitation[area_privativa_m2]] }
    when "Dimensões e estrutura física"
      { mode: "positive_any", names: %w[habitation[area_privativa_m2] habitation[area_total_m2] habitation[dormitorios_qtd] habitation[suites_qtd] habitation[salas_qtd] habitation[banheiros_qtd] habitation[vagas_qtd]] }
    when "Tipo de vaga"
      { mode: "any_present", names: %w[habitation[tipo_vaga]] }
    when "Vaga de garagem"
      { mode: "positive_any", names: %w[habitation[vagas_qtd]] }
    when "Box"
      { mode: "any_present", names: %w[habitation[numero_box]] }
    when "Situação"
      { mode: "any_present", names: %w[habitation[situacao]] }
    when "Ocupação"
      { mode: "any_present", names: %w[habitation[ocupacao_status]] }
    when "Mais características"
      { mode: "checked_any", names: %w[habitation[caracteristicas][]] }
    when "Infraestrutura & Lazer"
      { mode: "checked_any", names: %w[habitation[infra_estrutura][]] }
    when /\AInforme o valor de venda/, /\AInforme um valor de venda/
      { mode: "positive_any", names: %w[habitation[valor_venda_formatted]] }
    when /\AInforme o valor de locação/, /\AInforme um valor de locação/
      { mode: "positive_any", names: %w[habitation[valor_locacao_formatted]] }
    when "Financeiro e valores"
      { mode: "positive_any", names: %w[habitation[valor_condominio_formatted] habitation[valor_iptu_formatted]] }
    when "Administração da locação"
      { mode: "any_present", names: %w[habitation[salute_rental_management_answer]] }
    when "Meio de garantia locatícia"
      { mode: "any_present", names: %w[habitation[rental_guarantee_method] habitation[rental_guarantee_method][] captacao[rental_guarantee_method] captacao[rental_guarantee_method][]] }
    when "Aceita permuta"
      { mode: "any_present", names: %w[habitation[aceita_permuta_answer]] }
    when "Quantidade de parcelas"
      { mode: "positive_any", names: %w[habitation[numero_prestacoes]] }
    when "Chaves"
      { mode: "any_present", names: %w[habitation[key_location]] }
    when "Dias de visita"
      { mode: "any_present", names: %w[habitation[observacoes_visitas]] }
    when "Fotos ou agenda com fotógrafo", "Agenda com fotógrafo"
      { mode: "any_present", names: %w[habitation[photo_flow_choice] habitation[photos][]] }
    when "Anexo da autorização do proprietário"
      { mode: "file_present", names: %w[habitation[autorizacoes_venda][]] }
    end
  end

  def labeled_unit_value(label, value)
    clean_value = value.to_s.strip.presence
    return if clean_value.blank?
    return clean_value if clean_value.match?(/\A#{Regexp.escape(label.to_s.delete_suffix("."))}\b/i)

    "#{label} #{clean_value}"
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
