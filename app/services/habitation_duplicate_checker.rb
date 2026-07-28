class HabitationDuplicateChecker
  Result = Struct.new(:complete, :matches, :comparison, keyword_init: true) do
    def duplicate?
      matches.any?
    end
  end

  def initialize(street:, number:, building:, unit:, status: nil, comparison: nil, ignored_id: nil, complement: nil, category: nil, tenant: nil)
    @street = street
    @number = number
    @building = building
    @unit = unit
    @status = status
    @comparison = normalize_comparison(comparison)
    @ignored_id = ignored_id
    @complement = complement
    @category = category
    @tenant = tenant || Current.tenant
    raise ArgumentError, "Tenant obrigatório para verificar duplicidade de imóvel" if @tenant.blank?
  end

  def call
    return Result.new(complete: false, matches: [], comparison: comparison) unless complete_identity?

    candidates = base_scope
      .where(street_match_sql("COALESCE(addresses.logradouro, habitations.endereco)"), street: normalize_street(@street))
      .where("#{normalized_sql("COALESCE(addresses.numero, habitations.numero)")} = :number", number: normalize(@number))
      .where(status: normalized_status)
      .where.not("habitations.status ~* ?", "suspenso|vendido|alugado")
      .limit(20)

    matches = candidates.select do |habitation|
      active_duplicate_candidate?(habitation) &&
        same_status?(habitation) &&
        same_identity?(habitation)
    end

    Result.new(complete: true, matches: matches, comparison: comparison)
  end

  private

  def base_scope
    scope = habitation_scope.left_outer_joins(:address).includes(:address, :admin_user)
    if @ignored_id.present?
      scope = scope.where.not(id: @ignored_id)
      ignored_group_uuid = habitation_scope.where(id: @ignored_id).pick(:intake_group_uuid)
      if ignored_group_uuid.present?
        scope = scope.where("habitations.intake_group_uuid IS NULL OR habitations.intake_group_uuid != ?", ignored_group_uuid)
      end
    end
    scope
  end

  def habitation_scope
    @tenant.habitations
  end

  def complete_identity?
    base_complete = [@street, @number].all? { |value| normalize(value).present? } && normalized_status.present?
    return false unless base_complete

    case comparison
    when :street
      true
    when :condominium_unit
      normalize_unit(@unit).present? || normalize(@complement).present?
    else
      normalized_expected_unit.present?
    end
  end

  def active_duplicate_candidate?(habitation)
    return false if draft_broker_intake?(habitation)
    return true if active_broker_intake?(habitation)

    !habitation.inactive_for_admin_card?
  end

  def active_broker_intake?(habitation)
    habitation.intake_origin == Habitation::INTAKE_ORIGIN_BROKER &&
      !habitation.intake_draft? &&
      !habitation.exibir_no_site_flag?
  end

  def draft_broker_intake?(habitation)
    habitation.intake_origin == Habitation::INTAKE_ORIGIN_BROKER && habitation.intake_draft?
  end

  def same_status?(habitation)
    Habitation.normalize_status(habitation.status).to_s == normalized_status
  end

  def same_identity?(habitation)
    case comparison
    when :unit
      same_unit?(habitation)
    when :condominium_unit
      same_condominium_unit?(habitation)
    else
      street_level_candidate?(habitation)
    end
  end

  def same_unit?(habitation)
    expected = normalized_expected_unit
    actual = normalized_candidate_unit(habitation)

    return false unless expected.present? && actual == expected

    return true unless normalize_unit(@unit).present? && normalize_unit(habitation.bloco).present?

    expected_complement = normalize(@complement)
    actual_complement = normalize(habitation.address&.complemento.presence || habitation.complemento)
    return true if expected_complement.blank? || actual_complement.blank?

    expected_complement == actual_complement
  end

  def same_condominium_unit?(habitation)
    normalize(@complement) == normalize(habitation.complemento) &&
      normalize_unit(@unit) == normalize_unit(habitation.bloco)
  end

  def street_level_candidate?(habitation)
    normalize_unit(habitation.bloco.presence || habitation.complemento).blank?
  end

  def comparison
    @comparison ||= if complement_block_category? && (normalize_unit(@unit).present? || normalize(@complement).present?)
                      :condominium_unit
                    elsif normalized_expected_unit.present?
                      :unit
                    else
                      :street
                    end
  end

  def normalize_comparison(value)
    case value.to_s
    when "unit"
      :unit
    when "street"
      :street
    when "condominium_unit"
      :condominium_unit
    end
  end

  def normalized_status
    @normalized_status ||= Habitation.normalize_status(@status).to_s
  end

  def normalize(value)
    I18n.transliterate(value.to_s.downcase).gsub(/[^a-z0-9]+/, "")
  end

  def normalize_street(value)
    strip_street_type(value).then { |street| normalize(street) }
  end

  def normalize_unit(value)
    normalize(value).sub(/\A(apartamento|apto|unidade|unid|un|bloco|bl|ap)/, "")
  end

  def normalized_expected_unit
    @normalized_expected_unit ||= normalize_unit(@unit).presence || normalize_apartment_unit_from_complement(@complement)
  end

  def normalized_candidate_unit(habitation)
    normalize_unit(habitation.bloco).presence ||
      normalize_apartment_unit_from_complement(habitation.address&.complemento) ||
      normalize_apartment_unit_from_complement(habitation.complemento)
  end

  def normalize_apartment_unit_from_complement(value)
    return unless apartment_unit_category?

    text = I18n.transliterate(value.to_s.downcase)
    token = text[/\b(?:apartamento|apto|unidade|unid|un|ap)\.?\s*([a-z]?\d+[a-z0-9-]*)\b/i, 1]
    token ||= text[/\b(\d{2,5}[a-z0-9-]*)\b/i, 1]
    normalize_unit(token)
  end

  def complement_block_category?
    normalized_category = I18n.transliterate(@category.to_s.downcase)
    normalized_category.include?("casa em condominio") || normalized_category.include?("terreno")
  end

  def apartment_unit_category?
    normalized_category = I18n.transliterate(@category.to_s.downcase)
    normalized_category.blank? || normalized_category.match?(/apartamento|cobertura|loft|studio/)
  end

  def normalized_sql(expression)
    "regexp_replace(unaccent(lower(COALESCE(#{expression}, ''))), '[^a-z0-9]+', '', 'g')"
  end

  def normalized_street_sql(expression)
    "regexp_replace(regexp_replace(unaccent(lower(COALESCE(#{expression}, ''))), " \
      "'^(rua|r|avenida|av|alameda|travessa|rodovia|estrada|servidao|servidão|beco|praca|praça)\\s+', '', 'i'), " \
      "'[^a-z0-9]+', '', 'g')"
  end

  def street_match_sql(expression)
    "(#{normalized_sql(expression)} = :street OR #{normalized_street_sql(expression)} = :street)"
  end

  def strip_street_type(value)
    value.to_s.sub(/\A\s*(rua|r\.?|avenida|av\.?|alameda|travessa|rodovia|estrada|servid[aã]o|beco|pra[çc]a)\s+/i, "")
  end
end
