module InterestIntelligence
  class Settings
    DEFAULTS = {
      "price_tolerance_percent" => 15,
      "minimum_match_score" => 65,
      "strong_interest_views" => 2,
      "max_suggestions" => 5,
      "broker_review_required" => true,
      "requires_public_tracking_consent" => true,
      "allow_direct_lead_message" => false,
      "idle_without_match_hours" => 48,
      "city_weight" => 25,
      "neighborhood_weight" => 20,
      "category_weight" => 20,
      "bedrooms_weight" => 15,
      "parking_weight" => 5,
      "price_weight" => 20
    }.freeze

    # Fonte única dos campos do formulário (labels, hints e limites).
    # Usada pelo partial compartilhado admin/shared/ai/_interest_intelligence_settings.
    NUMBER_FIELDS = [
      ["minimum_match_score", "Score mínimo", "Compatibilidade mínima para sugerir um imóvel ao lead.", 0, 100, "pts"],
      ["max_suggestions", "Máximo de sugestões", "Limite exibido na ficha do lead e usado nas ações.", 1, 20, nil],
      ["strong_interest_views", "Visualizações fortes", "Visitas ao mesmo tipo de imóvel para reforçar o sinal.", 1, 20, nil],
      ["price_tolerance_percent", "Tolerância de preço", "Margem aceita acima ou abaixo da faixa inferida.", 0, 100, "%"],
      ["idle_without_match_hours", "Lead parado sem match", "Janela usada em jornadas de recuperação quando não há imóvel aderente.", 1, 720, "horas"]
    ].freeze
    WEIGHT_FIELDS = {
      city_weight: "Cidade", neighborhood_weight: "Bairro", category_weight: "Tipo",
      bedrooms_weight: "Dormitórios", parking_weight: "Vagas", price_weight: "Preço"
    }.freeze
    SAFEGUARD_FIELDS = [
      ["broker_review_required", "Exigir revisão humana antes de comunicação ativa", "Mantém a inteligência como apoio de curadoria; mensagens para o lead devem passar pelo corretor ou gestor."],
      ["requires_public_tracking_consent", "Exigir consentimento no site público", "Mostra um aviso discreto antes de rastrear navegação anônima para personalização de atendimento."],
      ["allow_direct_lead_message", "Permitir envio direto ao lead quando não exigir revisão", "Use com cuidado. Com revisão humana ativa, a plataforma sempre cria rascunho/nota para o corretor."]
    ].freeze

    def self.current
      new(LayoutSetting.instance)
    end

    # Fonte única da normalização do formulário (limites e booleanos).
    # Usada por Admin::AiIntegrationsController (aba Leads).
    def self.normalize_form_params(attributes)
      if attributes[:interest_intelligence_instructions].to_s.strip == SystemInstructions::DEFAULT_TEXT.strip
        attributes[:interest_intelligence_instructions] = nil
      end

      raw_settings = attributes[:interest_intelligence_settings].to_h
      attributes[:interest_intelligence_settings] = normalize_settings(raw_settings) if raw_settings.present?
      attributes
    end

    def self.normalize_settings(raw_settings)
      raw_settings = raw_settings.to_h
      {
        "price_tolerance_percent" => clamp_integer(raw_settings["price_tolerance_percent"], DEFAULTS["price_tolerance_percent"], 0, 100),
        "minimum_match_score" => clamp_integer(raw_settings["minimum_match_score"], DEFAULTS["minimum_match_score"], 0, 100),
        "strong_interest_views" => clamp_integer(raw_settings["strong_interest_views"], DEFAULTS["strong_interest_views"], 1, 20),
        "max_suggestions" => clamp_integer(raw_settings["max_suggestions"], DEFAULTS["max_suggestions"], 1, 20),
        "idle_without_match_hours" => clamp_integer(raw_settings["idle_without_match_hours"], DEFAULTS["idle_without_match_hours"], 1, 720),
        "city_weight" => clamp_integer(raw_settings["city_weight"], DEFAULTS["city_weight"], 0, 100),
        "neighborhood_weight" => clamp_integer(raw_settings["neighborhood_weight"], DEFAULTS["neighborhood_weight"], 0, 100),
        "category_weight" => clamp_integer(raw_settings["category_weight"], DEFAULTS["category_weight"], 0, 100),
        "bedrooms_weight" => clamp_integer(raw_settings["bedrooms_weight"], DEFAULTS["bedrooms_weight"], 0, 100),
        "parking_weight" => clamp_integer(raw_settings["parking_weight"], DEFAULTS["parking_weight"], 0, 100),
        "price_weight" => clamp_integer(raw_settings["price_weight"], DEFAULTS["price_weight"], 0, 100),
        "broker_review_required" => ActiveModel::Type::Boolean.new.cast(raw_settings["broker_review_required"]),
        "requires_public_tracking_consent" => ActiveModel::Type::Boolean.new.cast(raw_settings["requires_public_tracking_consent"]),
        "allow_direct_lead_message" => ActiveModel::Type::Boolean.new.cast(raw_settings["allow_direct_lead_message"])
      }
    end

    def self.clamp_integer(value, fallback, min, max)
      number = Integer(value.presence || fallback)
      [[number, min].max, max].min
    rescue ArgumentError, TypeError
      fallback
    end

    def initialize(layout_setting)
      @layout_setting = layout_setting
    end

    def enabled?
      return true unless @layout_setting.respond_to?(:interest_intelligence_enabled)

      ActiveModel::Type::Boolean.new.cast(@layout_setting.interest_intelligence_enabled)
    end

    def [](key)
      settings.fetch(key.to_s, DEFAULTS[key.to_s])
    end

    def settings
      DEFAULTS.merge(@layout_setting.interest_intelligence_settings.to_h)
    end

    def instructions
      InterestIntelligence::SystemInstructions.effective_text(@layout_setting)
    end

    def enabled_value?(key)
      ActiveModel::Type::Boolean.new.cast(self[key])
    end
  end
end
