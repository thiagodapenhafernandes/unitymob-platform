require "rails_helper"

RSpec.describe Ai::ModuleConfiguration do
  let(:tenant) { create(:admin_user, :admin).tenant }

  it "preserva provedor e modelos existentes enquanto não houver vínculos" do
    Setting.set(Ai::Provider::SETTING, "muse", tenant: tenant)
    Setting.set(Ai::Provider::MUSE_MODEL_SETTING, "muse-custom", tenant: tenant)
    Setting.set(Ai::Provider::MUSE_VOICE_MODEL_SETTING, "muse-interpretation", tenant: tenant)
    Setting.set(Ai::Provider::MUSE_VOICE_TRANSCRIPTION_MODEL_SETTING, "muse-transcription", tenant: tenant)

    described_class::MODULES.each do |key, metadata|
      configuration = described_class.new(key, tenant: tenant)
      expect(configuration.provider.key).to eq("muse")
      expect(configuration.model).to eq({ content: "muse-custom", interpretation: "muse-interpretation", transcription: "muse-transcription" }.fetch(metadata[:kind]))
    end
  end

  it "resolve cliente, token, modelo e fallback pelo vínculo sem alterar os outros módulos ou tenants" do
    other_tenant = Tenant.create!(name: "Outra conta", slug: "other-ai-#{SecureRandom.hex(4)}")
    Setting.set(Ai::PropertyContentService::API_KEY_SETTING, "openai-token", tenant: tenant)
    Setting.set(Ai::Provider::MUSE_API_KEY_SETTING, "muse-token", tenant: tenant)
    described_class.save!({ "seo" => { "provider" => "muse", "model" => "muse-custom" } }, tenant: tenant)

    seo = described_class.new(:seo, tenant: tenant)
    expect(seo.build_client).to be_a(MetaAi::Client)
    expect(seo.api_key).to eq("muse-token")
    expect(seo.resolved_model).to eq("muse-custom")
    expect(seo.fallback_model).to eq(MetaAi::ModelCatalog::RESPONSE_FALLBACK_MODEL)
    expect(described_class.new(:property_content, tenant: tenant).api_key).to eq("openai-token")
    expect(described_class.new(:seo, tenant: other_tenant).provider.key).to eq("openai")
    expect(described_class.new(:seo, tenant: other_tenant).api_key).to eq("")
  end

  it "mantém credenciais dedicadas de voz no mesmo provedor e resolve transcrição automática" do
    Setting.set(Ai::Provider::MUSE_API_KEY_SETTING, "general", tenant: tenant)
    Setting.set(Ai::Provider::MUSE_VOICE_API_KEY_SETTING, "voice", tenant: tenant)
    described_class.save!({ "property_search_transcription" => { "provider" => "muse", "model" => Ai::Provider::AUTOMATIC_VALUE } }, tenant: tenant)
    configuration = described_class.new(:property_search_transcription, tenant: tenant)
    expect(configuration.api_key).to eq("voice")
    expect(configuration.resolved_model).to eq(MetaAi::ModelCatalog::TRANSCRIPTION_FALLBACK_MODEL)
    expect(configuration.fallback_model).to be_nil
    expect(Ai::PropertySearch::Configuration.resolved_transcription_model(tenant: tenant)).to eq(configuration.resolved_model)
  end

  it "herda mudanças no padrão e permite voltar ao vínculo herdado preservando os demais" do
    described_class.save!({ "seo" => { "provider" => "muse", "model" => "muse-custom" } }, tenant: tenant)
    described_class.save!({ "seo" => { "provider" => "", "model" => "" }, "interest_summary" => { "provider" => "openai", "model" => "gpt-custom" } }, tenant: tenant)
    Setting.set(Ai::Provider::SETTING, "muse", tenant: tenant)
    expect(described_class.new(:seo, tenant: tenant).provider.key).to eq("muse")
    expect(described_class.new(:interest_summary, tenant: tenant).provider.key).to eq("openai")
  end

  it "rejeita entradas inválidas sem salvar parte dos vínculos" do
    [ { "unknown" => {} }, { "seo" => { "provider" => "unknown" } }, { "seo" => { "model" => "modelo com espaços" } }, { "seo" => { "model" => "x" * 201 } } ].each do |attributes|
      expect { described_class.save!(attributes, tenant: tenant) }.to raise_error(ArgumentError)
    end
    expect(described_class.bindings(tenant: tenant)).to eq({})
  end

  it "não usa vínculos ou tokens globais quando a conta não configurou IA" do
    Setting.set(described_class::SETTING, { seo: { provider: "muse", model: "global" } }.to_json, tenant: nil)
    Setting.set(Ai::PropertyContentService::API_KEY_SETTING, "global-token", tenant: nil)
    expect(described_class.new(:seo, tenant: tenant).connected?).to be(false)
    expect(described_class.new(:seo, tenant: tenant).provider.key).to eq("openai")
  end
end
