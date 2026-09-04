require "rails_helper"

RSpec.describe PropertySetting, type: :model do
  describe ".instance" do
    it "creates a singleton with the default watermark position" do
      setting = described_class.instance

      expect(setting).to be_persisted
      expect(setting.watermark_position).to be_in(PropertySetting::WATERMARK_POSITIONS.keys)
      expect(setting.watermark_size_percentage).to be_between(PropertySetting::WATERMARK_SIZE_RANGE.begin, PropertySetting::WATERMARK_SIZE_RANGE.end)
      expect(setting.watermark_opacity_percentage).to be_between(PropertySetting::WATERMARK_OPACITY_RANGE.begin, PropertySetting::WATERMARK_OPACITY_RANGE.end)
      expect(setting.ai_property_search_allow_flexible_results).to be(true)
  end
  end

  it "aceita as cinco posições predefinidas da marca d'água" do
    PropertySetting::WATERMARK_POSITIONS.keys.each do |position|
      setting = described_class.new(watermark_position: position)

      expect(setting).to be_valid
    end
  end

  it "rejeita posições de marca d'água fora dos presets" do
    setting = described_class.new(watermark_position: "top_left")
    setting.watermark_position = "free_drag"

    expect(setting).not_to be_valid
    expect(setting.errors[:watermark_position]).to be_present
  end

  it "validates watermark size and opacity ranges" do
    setting = described_class.new(
      watermark_position: "center",
      watermark_size_percentage: 125,
      watermark_opacity_percentage: 0
    )

    expect(setting).not_to be_valid
    expect(setting.errors[:watermark_size_percentage]).to be_present
    expect(setting.errors[:watermark_opacity_percentage]).to be_present
  end

  it "valida faixas dos parâmetros da OpenAI na busca inteligente" do
    setting = described_class.instance
    setting.assign_attributes(
      ai_property_search_temperature: 2.1,
      ai_property_search_top_p: 1.1,
      ai_property_search_frequency_penalty: 2.1,
      ai_property_search_presence_penalty: -2.1
    )

    expect(setting).not_to be_valid
    expect(setting.errors[:ai_property_search_temperature]).to be_present
    expect(setting.errors[:ai_property_search_top_p]).to be_present
    expect(setting.errors[:ai_property_search_frequency_penalty]).to be_present
    expect(setting.errors[:ai_property_search_presence_penalty]).to be_present
  end


  it "mantém a configuração da busca inteligente isolada por tenant" do
    first_tenant = Tenant.create!(name: "Conta IA A", slug: "conta-ia-a", active: true)
    second_tenant = Tenant.create!(name: "Conta IA B", slug: "conta-ia-b", active: true)

    first = described_class.instance(tenant: first_tenant)
    second = described_class.instance(tenant: second_tenant)
    first.update!(ai_property_search_enabled: true, ai_property_search_welcome_message: "Mensagem A")

    expect(first.reload.ai_property_search_enabled).to be(true)
    expect(second.reload.ai_property_search_enabled).to be(false)
    expect(second.ai_property_search_welcome_message).not_to eq("Mensagem A")
  end

  it "usa instruções padrão alinhadas com busca imediata sem sobrescrever customizações" do
    setting = described_class.new(watermark_position: "bottom_left")
    setting.valid?

    expect(setting.ai_property_search_instructions).to include("Nunca interrompa a busca com pergunta complementar")
    expect(setting.ai_property_search_instructions).to include("Busca específica")
    expect(setting.ai_property_search_instructions).to include("property_code")
    expect(setting.ai_property_search_instructions).to include("Retorne clarifying_question como null")
    expect(setting.ai_property_search_instructions).not_to include("solicite esclarecimento")

    setting.ai_property_search_instructions = "Minha instrução customizada"
    setting.valid?

    expect(setting.ai_property_search_instructions).to eq("Minha instrução customizada")
  end

  it "atualiza somente o texto padrão legado da busca inteligente" do
    setting = described_class.new(
      watermark_position: "bottom_left",
      ai_property_search_instructions: "  #{described_class::LEGACY_AI_PROPERTY_SEARCH_INSTRUCTIONS.gsub("\n", "\r\n  ")}  "
    )

    setting.valid?

    expect(setting.ai_property_search_instructions).to eq(described_class::DEFAULT_AI_PROPERTY_SEARCH_INSTRUCTIONS)
  end

  it "atualiza somente o texto padrão anterior da busca inteligente" do
    setting = described_class.new(
      watermark_position: "bottom_left",
      ai_property_search_instructions: "  #{described_class::PREVIOUS_DEFAULT_AI_PROPERTY_SEARCH_INSTRUCTIONS.gsub("\n", "\r\n  ")}  "
    )

    setting.valid?

    expect(setting.ai_property_search_instructions).to eq(described_class::DEFAULT_AI_PROPERTY_SEARCH_INSTRUCTIONS)
  end

  it "rejeita allowlists, limites e fontes inválidas" do
    setting = described_class.instance
    setting.assign_attributes(
      ai_property_search_allowed_fields: ["sql_expression"],
      ai_property_search_max_results: 500,
      ai_property_search_data_source: "direct_sql",
      ai_property_search_share_max_properties: 101,
      ai_property_search_share_expiration_days: 0,
      ai_property_search_visitor_recognition_days: 731,
      ai_property_search_broker_events_limit: 21,
      ai_property_search_catalog_property_types_limit: 0,
      ai_property_search_catalog_cities_limit: 51,
      ai_property_search_catalog_neighborhoods_limit: 0,
      ai_property_search_catalog_developments_limit: 51,
      ai_property_search_catalog_feature_terms_limit: 0,
      ai_property_search_catalog_alias_names_limit: 21
    )

    expect(setting).not_to be_valid
    expect(setting.errors[:ai_property_search_allowed_fields]).to be_present
    expect(setting.errors[:ai_property_search_max_results]).to be_present
    expect(setting.errors[:ai_property_search_data_source]).to be_present
    expect(setting.errors[:ai_property_search_share_max_properties]).to be_present
    expect(setting.errors[:ai_property_search_share_expiration_days]).to be_present
    expect(setting.errors[:ai_property_search_visitor_recognition_days]).to be_present
    expect(setting.errors[:ai_property_search_broker_events_limit]).to be_present
    expect(setting.errors[:ai_property_search_catalog_property_types_limit]).to be_present
    expect(setting.errors[:ai_property_search_catalog_cities_limit]).to be_present
    expect(setting.errors[:ai_property_search_catalog_neighborhoods_limit]).to be_present
    expect(setting.errors[:ai_property_search_catalog_developments_limit]).to be_present
    expect(setting.errors[:ai_property_search_catalog_feature_terms_limit]).to be_present
    expect(setting.errors[:ai_property_search_catalog_alias_names_limit]).to be_present
  end

  it "usa os limites padrão do contexto do catálogo para não exigir configuração manual" do
    setting = described_class.instance

    expect(setting.ai_property_search_catalog_context_limits).to eq(
      property_types: 12,
      cities: 12,
      neighborhoods: 18,
      developments: 12,
      feature_terms: 20,
      alias_names: 5
    )
  end
end
