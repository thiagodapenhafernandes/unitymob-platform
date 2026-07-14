class PropertyReviewPolicyResolver
  Result = Data.define(
    :policy,
    :property_setting,
    :source,
    :registration_type,
    :category,
    :modality,
    :required_checks,
    :applicable_checks,
    :ignored_checks,
    :returnable_sections
  ) do
    def specific?
      source == :specific
    end

    def source_label
      specific? ? "Regra própria" : "Regra padrão da conta"
    end
  end

  IgnoredCheck = Data.define(:key, :label, :reason)

  def self.call(...)
    new(...).call
  end

  def self.for_habitation(habitation, property_setting: nil)
    setting = property_setting || PropertySetting.instance(tenant: habitation.tenant)
    call(
      tenant: habitation.tenant,
      property_setting: setting,
      registration_type: PropertyReviewPolicy.registration_type_for_habitation(habitation),
      category: habitation.categoria,
      modality: habitation.modalidade,
      habitation: habitation
    )
  end

  def initialize(tenant:, property_setting:, registration_type:, category: nil, modality: nil, habitation: nil)
    @tenant = tenant
    @property_setting = property_setting
    @registration_type = registration_type.to_s.presence || "apartamentos"
    @category = category.to_s.strip.presence
    @modality = modality.to_s.strip.presence
    @habitation = habitation
  end

  def call
    policy = find_policy
    source = policy ? :specific : :fallback
    rule = policy || property_setting
    required_checks = rule.active_broker_capture_checks
    applicable, ignored = partition_checks(required_checks)

    Result.new(
      policy: policy,
      property_setting: property_setting,
      source: source,
      registration_type: registration_type,
      category: category,
      modality: modality,
      required_checks: required_checks,
      applicable_checks: applicable,
      ignored_checks: ignored,
      returnable_sections: rule.active_returnable_intake_edit_sections
    )
  end

  private

  attr_reader :tenant, :property_setting, :registration_type, :category, :modality, :habitation

  def find_policy
    candidates.each do |context|
      policy = PropertyReviewPolicy.active.find_by(
        tenant: tenant,
        registration_type: context.fetch(:registration_type),
        category: context.fetch(:category),
        modality: context.fetch(:modality)
      )
      return policy if policy
    end
    nil
  end

  def candidates
    [
      { registration_type: registration_type, category: category, modality: modality },
      { registration_type: registration_type, category: category, modality: nil },
      { registration_type: registration_type, category: nil, modality: nil }
    ]
  end

  def projection_habitation
    @projection_habitation ||= begin
      return habitation if habitation

      record = tenant.habitations.new
      record.categoria = category if category.present?
      record.modalidade = modality if modality.present?
      record
    end
  end

  def partition_checks(required_checks)
    Array(required_checks).each_with_object([[], []]) do |key, (applicable, ignored)|
      reason = ignored_reason_for(key)
      label = PropertySetting::BROKER_INTAKE_CHECK_OPTIONS.fetch(key.to_s, key.to_s)

      if reason
        ignored << IgnoredCheck.new(key: key.to_s, label: label, reason: reason)
      else
        applicable << [key.to_s, label]
      end
    end
  end

  def ignored_reason_for(key)
    h = projection_habitation

    case key.to_s
    when "empreendimento"
      "esta categoria não exige empreendimento" unless h.requires_intake_development_name?
    when "unidade"
      "esta categoria não exige número de unidade" unless h.requires_unit_number?
    when "area"
      nil
    when "vagas", "tipo_vaga", "box"
      "esta categoria não exige dados de vaga no checklist" unless h.requires_parking_info?
    when "situacao", "ocupacao"
      "terrenos não usam esta etapa operacional" if h.property_kind_terreno?
    when "infraestrutura"
      "esta categoria não usa infraestrutura de edifício" unless h.uses_building_infrastructure?
    when "financeiro"
      "esta categoria não exige condomínio/IPTU no checklist" unless h.requires_intake_expense_amount?
    when "admin_locacao", "garantia_locaticia"
      "esta modalidade não é locação" unless h.rental_intake?
    when "permuta"
      "esta modalidade não é venda" unless h.sale_intake?
    when "parcelamento"
      "só é cobrado quando o captador informa que aceita parcelamento"
    when "chaves"
      "esta categoria não exige local das chaves" unless h.requires_intake_key_location?
    when "visitas"
      "só é cobrado quando a visita não for marcada como dispensada"
    end
  end
end
