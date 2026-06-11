class HabitationDuplicateChecker
  Result = Struct.new(:complete, :matches, :comparison, keyword_init: true) do
    def duplicate?
      matches.any?
    end
  end

  def initialize(street:, number:, building:, unit:, status: nil, comparison: nil, ignored_id: nil, complement: nil, category: nil)
    @street = street
    @number = number
    @building = building
    @unit = unit
    @status = status
    @comparison = normalize_comparison(comparison)
    @ignored_id = ignored_id
    @complement = complement
    @category = category
  end

  def call
    return Result.new(complete: false, matches: [], comparison: comparison) unless complete_identity?

    candidates = base_scope
      .where("#{normalized_sql("COALESCE(addresses.logradouro, habitations.endereco)")} = :street", street: normalize(@street))
      .where("#{normalized_sql("COALESCE(addresses.numero, habitations.numero)")} = :number", number: normalize(@number))
      .where(status: normalized_status)
      .where(exibir_no_site_flag: true)
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
    scope = Habitation.left_outer_joins(:address).includes(:address, :admin_user)
    if @ignored_id.present?
      scope = scope.where.not(id: @ignored_id)
      ignored_group_uuid = Habitation.where(id: @ignored_id).pick(:intake_group_uuid)
      if ignored_group_uuid.present?
        scope = scope.where("habitations.intake_group_uuid IS NULL OR habitations.intake_group_uuid != ?", ignored_group_uuid)
      end
    end
    scope
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
      normalize_unit(@unit).present?
    end
  end

  def active_duplicate_candidate?(habitation)
    !habitation.unavailable_for_duplicate_check?
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
    expected = normalize_unit(@unit)
    actual = normalize_unit(habitation.bloco.presence || habitation.complemento)

    expected.present? && actual == expected
  end

  def same_condominium_unit?(habitation)
    normalize(@complement) == normalize(habitation.complemento) &&
      normalize_unit(@unit) == normalize_unit(habitation.bloco)
  end

  def street_level_candidate?(habitation)
    normalize_unit(habitation.bloco.presence || habitation.complemento).blank?
  end

  def comparison
    @comparison ||= if condominium_house_category? && (normalize_unit(@unit).present? || normalize(@complement).present?)
                      :condominium_unit
                    elsif normalize_unit(@unit).present?
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

  def normalize_unit(value)
    normalize(value).sub(/\A(apartamento|apto|unidade|unid|un|bloco|bl|ap)/, "")
  end

  def condominium_house_category?
    normalized_category = I18n.transliterate(@category.to_s.downcase)
    normalized_category.include?("casa em condominio")
  end

  def normalized_sql(expression)
    "regexp_replace(unaccent(lower(COALESCE(#{expression}, ''))), '[^a-z0-9]+', '', 'g')"
  end
end
