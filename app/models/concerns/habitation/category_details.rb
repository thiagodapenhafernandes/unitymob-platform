# frozen_string_literal: true

module Habitation::CategoryDetails
  extend ActiveSupport::Concern

  # Somente medidas, capacidades e complementos sem equivalente ganham colunas.
  # As seleções continuam nos checklists existentes.
  WAREHOUSE_CATEGORIES = ["Galpão", "Galpão em Condomínio"].freeze
  LAND_CATEGORIES = ["Área", "Terreno", "Terreno em Condomínio"].freeze
  DETAIL_FIELDS = {
    area_armazenagem_m2: { label: "Área de armazenagem (m²)", group: :warehouse, measure: true },
    pe_direito_livre_m: { label: "Pé-direito livre (m)", group: :warehouse, measure: true },
    altura_armazenagem_m: { label: "Altura máxima de armazenagem (m)", group: :warehouse, measure: true },
    outra_operacao_galpao: { label: "Outra operação", group: :warehouse },
    capacidade_piso_ton_m2: { label: "Capacidade do piso (ton/m²)", group: :warehouse, measure: true },
    capacidade_eletrica_kva: { label: "Capacidade elétrica (kVA)", group: :warehouse, measure: true },
    docas_qtd: { label: "Quantidade de docas", group: :warehouse, count: true },
    setor_terreno: { label: "Área / setor", group: :land },
    lateral_1_terreno_m: { label: "Lateral 1 (m)", group: :land, measure: true },
    lateral_2_terreno_m: { label: "Lateral 2 (m)", group: :land, measure: true }
  }.freeze

  WAREHOUSE_TYPE_OPTIONS = [
    "Galpão Logístico/Industrial em Condomínio",
    "Galpão Pré-moldado Comum",
    "Galpão Cross-Docking",
    "Galpão Autoportantes",
    "Galpão Lonado (ou Sanfonado)",
    "Galpão de Alvenaria Tradicional",
    "Galpão de Estrutura Metálica com Telhas de Zinco",
    "Barracão Simples de Madeira"
  ].freeze
  LEGACY_WAREHOUSE_TYPE_OPTIONS = [
    "Galpão logístico/industrial em condomínio",
    "Galpão pré-moldado comum",
    "Galpão cross-docking",
    "Galpão autoportante",
    "Galpão lonado/sanfonado",
    "Galpão de alvenaria tradicional",
    "Galpão de estrutura metálica",
    "Barracão simples"
  ].freeze
  WAREHOUSE_TYPE_CHOICE_VALUES = (WAREHOUSE_TYPE_OPTIONS + LEGACY_WAREHOUSE_TYPE_OPTIONS).freeze

  # Os nomes são os mesmos já utilizados pelos checklists/importações.
  WAREHOUSE_SINGLE_CHOICES = {
    "Tipo de galpão" => WAREHOUSE_TYPE_CHOICE_VALUES,
    "Classificação" => ["Classe AAA", "Classe A+", "Classe A"],
    "Tipo de piso" => ["Piso industrial", "Piso de concreto simples", "Chão batido"],
    "Alimentação elétrica" => ["Energia monofásica", "Energia bifásica", "Energia trifásica"]
  }.freeze
  INTERNAL_EQUIPMENT_OPTIONS = ["Persianas elétricas", "Escada interna"].freeze
  EV_CHARGING_OPTION = "Ponto de recarga para veículo elétrico".freeze
  OTHER_OPERATION = "Outra operação".freeze

  WAREHOUSE_FEATURES = [
    "Sistemas de vigilância 24h",
    "CFTV",
    "Câmeras IP 4K com visão noturna 360°",
    "Câmeras com Reconhecimento Facial",
    "Câmeras LPR (leitura de Placas)",
    "Alarmes Convencionais",
    "Alarmes endereçável (inteligente)",
    "Controle de acesso com reconhecimento facial",
    "Sistema J-1 (Incombustíveis)",
    "Sistema J-2 (Baixo)",
    "Sistema J-3 (Médio)",
    "Sistema J-4 (Alto/Elevado)",
    "Sensores IoT monitorando calor em tempo real",
    "Integração com IA (detecção proativa)",
    "Sistemas híbridos água + gás",
    "Modelagem digital do incêndio (Fire Engineering)",
    "Sistema Sprinklers",
    "Reservatório de Água",
    "Iluminação Natural (zenital, telhas translúcidas)",
    "Iluminação Artificial (LED)",
    "Venezianas de Entrada de Ar",
    "Lanternim de Cobertura",
    "Sistemas de ventilação natural/forçada",
    "Exaustores",
    "Sistemas de climatização para controle de temperatura e umidade",
    "Rampas de acesso",
    "Banheiros adaptados",
    "Pátios amplos para manobras de caminhões",
    "Salas de reunião",
    "Refeitório",
    "Vestiários",
    "Áreas de convivência para funcionários",
    "Mezanino",
    "Alpendre",
    "Isolamento térmico",
    "Isolamento acústico"
  ].freeze
  WAREHOUSE_INFRA = [
    "Heliponto",
    "Salão de Festas",
    "Espaço eventos",
    "Quadras esportes",
    "Vestiários",
    "Estacionamento",
    "Restaurante",
    "Salas Administração",
    "Área de convivência",
    "Área S.O",
    "Coworking",
    "Sala jogos",
    "Salas descanso",
    "Balança",
    "Auditório",
    "Salas reuniões",
    "Área manobra"
  ].freeze
  COMMERCIAL_FEATURES = [
    "Mezanino",
    "Depósito",
    "Escritório",
    "Cozinha",
    "Recepção",
    "Vitrine",
    "Fachada comercial",
    "Acessibilidade",
    "Elevador",
    "Ar-condicionado",
    "Infraestrutura para ar-condicionado",
    "Cabeamento estruturado",
    "Internet",
    "Sistema de segurança",
    "Câmeras",
    "Alarme",
    "Controle de acesso",
    "Estacionamento",
    "Estacionamento para clientes",
    "Banheiro para PCD",
    "Área de carga e descarga",
    "Portaria 24h",
    "Mobiliado",
    "Sem mobília"
  ].freeze
  LAND_FEATURES = [
    "Rede de água",
    "rede de esgoto",
    "Energia elétrica",
    "Calçada",
    "Drenagem pluvial",
    "Via asfaltada",
    "Via com Calçamento de Pedra/Lajota",
    "Via de Terra Compactada"
  ].freeze
  LAND_INFRA = [
    "Piscina",
    "Academia",
    "Pista caminhada",
    "Marina",
    "Campo golf",
    "Quadra padel",
    "Quadra tênis",
    "Quadra poliesportiva",
    "Pavimentação",
    "Brinquedoteca",
    "Churrasqueira coletiva",
    "Cinema",
    "Segurança 24h",
    "Guarita",
    "Heliponto",
    "Playground",
    "Iluminação"
  ].freeze

  COMMERCIAL_UNIT_CATEGORIES = ["Sala Comercial", "Ponto Comercial", "Loja"].freeze
  RESIDENTIAL_COUNTS = %i[dormitorios_qtd suites_qtd demi_suites_qtd varandas_qtd hidromassagem_qtd].freeze
  UNIT_FIELDS = %i[salas_qtd banheiros_qtd vagas_qtd tipo_vaga numero_box andar].freeze
  LAND_MEASURES = %i[frente_terreno_m fundo_terreno_m].freeze

  included do
    attr_accessor :confirm_category_change, :category_transition_locked_fields, :category_form_submission, :intake_unit_conversion
    before_validation :apply_confirmed_category_transition
    after_validation :restore_failed_category_transition
    before_validation :normalize_category_details
    validate :validate_category_details
    validates(*LAND_MEASURES, numericality: { greater_than: 0 }, allow_nil: true, if: -> { LAND_MEASURES.any? { |name| will_save_change_to_attribute?(name) } })
    (RESIDENTIAL_COUNTS + %i[salas_qtd banheiros_qtd vagas_qtd elevadores_qtd andares_qtd aptos_andar aptos_edificio]).each do |name|
      validates name, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true,
        if: -> { category_form_submission && will_save_change_to_attribute?(name) && category_field_applicable?(name) }
    end
    %i[area_privativa_m2 area_total_m2 area_terreno_m2 area_util_m2].each do |name|
      validates name, numericality: { greater_than: 0 }, allow_nil: true,
        if: -> { category_form_submission && will_save_change_to_attribute?(name) }
    end
    DETAIL_FIELDS.each do |name, config|
      next unless config[:measure] || config[:count]

      numericality = config[:count] ? { only_integer: true, greater_than_or_equal_to: 0 } : { greater_than: 0 }
      validates name, numericality: numericality, allow_nil: true
    end
  end

  def category_detail_applicable?(name)
    config = DETAIL_FIELDS.fetch(name.to_sym)
    category = self.class.normalize_registration_category(categoria)
    if config[:group] == :warehouse
      return false unless WAREHOUSE_CATEGORIES.include?(category)
      return other_warehouse_operation? if name.to_sym == :outra_operacao_galpao
      return true
    end
    return false unless LAND_CATEGORIES.include?(category)

    true
  end

  def category_field_applicable?(name)
    name = name.to_sym
    return category_detail_applicable?(name) if DETAIL_FIELDS.key?(name)
    return registration_group == "imoveis_residenciais" if RESIDENTIAL_COUNTS.include?(name)
    return !registration_group.in?(%w[terrenos empreendimento]) if UNIT_FIELDS.include?(name)
    return registration_group == "terrenos" if LAND_MEASURES.include?(name)
    return registration_group != "empreendimento" if name == :caracteristicas
    true
  end

  def category_checklist_options(kind)
    category = self.class.normalize_registration_category(categoria)
    options = if WAREHOUSE_CATEGORIES.include?(category)
      kind == "feature" ? (self.class::CORPORATE_FEATURE_OPTIONS + WAREHOUSE_FEATURES + [OTHER_OPERATION]) : (self.class::CORPORATE_INFRASTRUCTURE_OPTIONS + WAREHOUSE_INFRA + ["Energia monofásica", "Energia bifásica", "Cobertura com previsão fotovoltaica"])
    elsif COMMERCIAL_UNIT_CATEGORIES.include?(category)
      kind == "feature" ? COMMERCIAL_FEATURES : self.class::COMMERCIAL_INFRASTRUCTURE_OPTIONS
    elsif LAND_CATEGORIES.include?(category)
      kind == "feature" ? LAND_FEATURES : LAND_INFRA
    elsif registration_group == "empreendimento"
      kind == "feature" ? [] : LAND_INFRA + standard_infrastructure_options
    end
    return if options.nil?

    normalizer = AttributeOptions::HabitationFeatureNormalizer
    if registration_group != "empreendimento"
      existing = kind == "feature" ? standard_feature_options : standard_infrastructure_options
      opposite = kind == "feature" ? standard_infrastructure_options : standard_feature_options
      existing = normalizer.normalize_list(existing, category: kind)
      opposite = normalizer.normalize_list(opposite, category: kind)
      # Preserva opções antigas no seu checklist; só retira repetições novas.
      normalizer.normalize_list(existing + options, category: kind) - (opposite - existing)
    else
      normalizer.normalize_list(options, category: kind)
    end
  end

  def category_known_checklist_options
    INTERNAL_EQUIPMENT_OPTIONS + [EV_CHARGING_OPTION] + WAREHOUSE_FEATURES + WAREHOUSE_INFRA + [OTHER_OPERATION, "Energia monofásica", "Energia bifásica", "Cobertura com previsão fotovoltaica"] + COMMERCIAL_FEATURES + LAND_FEATURES + LAND_INFRA +
      self.class::CORPORATE_FEATURE_OPTIONS + self.class::CORPORATE_INFRASTRUCTURE_OPTIONS +
      self.class::COMMERCIAL_FEATURE_OPTIONS + self.class::COMMERCIAL_INFRASTRUCTURE_OPTIONS +
      self.class::LAND_FEATURE_OPTIONS + self.class::LAND_INFRASTRUCTURE_OPTIONS
  end

  def category_transition_checklists
    return {} unless persisted? && will_save_change_to_categoria?
    previous_category = self.class.new(categoria: categoria_in_database, registration_profile: registration_group)
    return {} if %w[feature infrastructure].all? { |kind| previous_category.category_checklist_options(kind) == category_checklist_options(kind) }
    { caracteristicas: "feature", infra_estrutura: "infrastructure" }.each_with_object({}) do |(name, kind), changes|
      allowed = category_checklist_options(kind)
      if allowed.nil?
        next if registration_group == "imoveis_residenciais"
        allowed = kind == "feature" ? standard_feature_options : standard_infrastructure_options
        next if allowed.empty?
      end
      normalizer = AttributeOptions::HabitationFeatureNormalizer
      values = normalize_feature_values(self[name], category: kind)
      allowed = normalizer.normalize_list(allowed, category: kind)
      known_values = normalizer.normalize_list(category_known_checklist_options, category: kind)
      kept = values.reject { |value| known_values.include?(value) && !allowed.include?(value) }
      kept = [] if name == :caracteristicas && registration_group == "empreendimento"
      previous = normalize_feature_values(attribute_in_database(name), category: kind)
      removed_previous = previous.any? { |value| known_values.include?(value) && !allowed.include?(value) }
      changes[name] = kept if kept != values || removed_previous
    end
  end

  def category_transition_fields
    (DETAIL_FIELDS.keys + RESIDENTIAL_COUNTS + UNIT_FIELDS + LAND_MEASURES + [:caracteristicas]).select do |name|
      !category_field_applicable?(name) && [self[name], attribute_in_database(name)].any? do |value|
        value.present? && (!(RESIDENTIAL_COUNTS + UNIT_FIELDS).include?(name) || value.to_s != "0")
      end
    end
  end

  def category_details_for_display
    (DETAIL_FIELDS.keys + LAND_MEASURES).each_with_object({}) do |name, result|
      result[name] = self[name] if category_field_applicable?(name) && self[name].present?
    end
  end

  def other_warehouse_operation?
    WAREHOUSE_CATEGORIES.include?(categoria) && normalize_feature_values(caracteristicas).include?(OTHER_OPERATION)
  end

  def selected_warehouse_type
    choices = AttributeOptions::HabitationFeatureNormalizer.normalize_list(WAREHOUSE_TYPE_CHOICE_VALUES)
    normalize_feature_values(caracteristicas).find { |value| choices.include?(value) }
  end

  def warehouse_exclusive_choice_group(value)
    WAREHOUSE_SINGLE_CHOICES.find { |_, values| AttributeOptions::HabitationFeatureNormalizer.normalize_list(values).include?(value) }&.first
  end

  private

  def apply_confirmed_category_transition
    @category_transition_snapshot = nil
    return unless persisted? && will_save_change_to_categoria?
    fields = category_transition_fields
    checklist_changes = category_transition_checklists
    fields |= checklist_changes.keys
    return if fields.empty?
    unless ActiveModel::Type::Boolean.new.cast(confirm_category_change)
      errors.add(:categoria, "confirme a retirada dos campos incompatíveis; os valores anteriores serão mantidos no histórico")
      return
    end
    if (fields.map(&:to_s) & Array(category_transition_locked_fields)).any?
      errors.add(:categoria, "não pode ser alterada porque há campos incompatíveis bloqueados para seu perfil")
      return
    end
    @category_transition_snapshot = fields.index_with { |name| self[name].deep_dup }
    fields.each { |name| public_send("#{name}=", checklist_changes.fetch(name) { self[name].is_a?(Array) || self[name].is_a?(Hash) ? [] : nil }) }
  end


  def restore_failed_category_transition
    return if errors.empty? || @category_transition_snapshot.nil?
    @category_transition_snapshot.each { |name, value| public_send("#{name}=", value) }
  end

  def normalize_category_details
    DETAIL_FIELDS.each do |name, config|
      next unless will_save_change_to_attribute?(name)
      next if config[:measure] || config[:count]

      self[name] = self[name].to_s.strip.presence
    end
  end

  def validate_category_details
    if persisted? && will_save_change_to_categoria? && !self.class::REGISTRATION_PROFILES.dig(registration_group, :categories).to_a.include?(categoria)
      errors.add(:categoria, "não pertence ao grupo de cadastro definido")
    end
    if will_save_change_to_caracteristicas? && !other_warehouse_operation?
      if outra_operacao_galpao.present? && Array(category_transition_locked_fields).include?("outra_operacao_galpao")
        errors.add(:caracteristicas, "não pode retirar Outra operação porque o complemento está bloqueado para seu perfil")
      else
        self.outra_operacao_galpao = nil
      end
    end
    (RESIDENTIAL_COUNTS + UNIT_FIELDS).each do |name|
      next unless category_form_submission || (persisted? && will_save_change_to_categoria?)
      next unless will_save_change_to_attribute?(name) && self[name].present? && self[name].to_s != "0"
      errors.add(name, "não se aplica à categoria selecionada") unless category_field_applicable?(name)
    end
    DETAIL_FIELDS.each_key do |name|
      value = self[name]
      next if value.blank?

      errors.add(name, "não se aplica à categoria selecionada") unless category_detail_applicable?(name)
    end

    if WAREHOUSE_CATEGORIES.include?(categoria)
      { caracteristicas: "feature", infra_estrutura: "infrastructure" }.each do |name, kind|
        next unless new_record? || will_save_change_to_attribute?(name)
        current = normalize_feature_values(self[name], category: kind)
        previous = normalize_feature_values(attribute_in_database(name), category: kind)
        WAREHOUSE_SINGLE_CHOICES.each do |label, options|
          choices = AttributeOptions::HabitationFeatureNormalizer.normalize_list(options, category: kind)
          selected = current & choices
          next if persisted? && selected.sort == (previous & choices).sort
          errors.add(name, "selecione apenas uma opção de #{label}") if selected.size > 1
        end
      end
    end

    furniture = normalize_feature_values(caracteristicas).map { |value| I18n.transliterate(value.to_s).downcase }
    if (new_record? || will_save_change_to_caracteristicas? || will_save_change_to_mobiliado_flag? || will_save_change_to_sem_mobilia_flag?) &&
        ((mobiliado_flag && sem_mobilia_flag) || (furniture.include?("mobiliado") && furniture.include?("sem mobilia")))
      errors.add(:caracteristicas, "não pode combinar Mobiliado e Sem mobília")
    end

    if other_warehouse_operation? && outra_operacao_galpao.blank?
      errors.add(:outra_operacao_galpao, "deve ser informada ao selecionar Outra operação")
    end
  end
end
