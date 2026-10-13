require "rails_helper"

RSpec.describe Ai::Provider do
  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }

  describe ".active_key" do
    it "usa OpenAI por padrão" do
      expect(described_class.active_key(tenant: tenant)).to eq("openai")
    end

    it "honra a seleção salva e rejeita valores desconhecidos" do
      Setting.set(described_class::SETTING, "muse", "Provedor", tenant: tenant)
      expect(described_class.active_key(tenant: tenant)).to eq("muse")

      Setting.set(described_class::SETTING, "inexistente", "Provedor", tenant: tenant)
      expect(described_class.active_key(tenant: tenant)).to eq("openai")
    end
  end

  describe ".active" do
    it "resolve cliente, catálogo e chaves do provedor ativo" do
      openai = described_class.active(tenant: tenant)

      expect(openai.key).to eq("openai")
      expect(openai.client_class).to eq(OpenAi::Client)
      expect(openai.catalog_class).to eq(OpenAi::ModelCatalog)
      expect(openai.api_key_setting).to eq(Ai::PropertyContentService::API_KEY_SETTING)

      Setting.set(described_class::SETTING, "muse", "Provedor", tenant: tenant)
      muse = described_class.active(tenant: tenant)

      expect(muse.key).to eq("muse")
      expect(muse.client_class).to eq(MetaAi::Client)
      expect(muse.catalog_class).to eq(MetaAi::ModelCatalog)
      expect(muse.default_model).to eq("muse-spark-1.3")
      expect(muse.default_transcription_model).to eq("muse-voice-transcribe-1.0")
    end
  end

  describe "delegação de credenciais" do
    it "lê token e modelo do namespace de cada provedor" do
      Setting.set(Ai::PropertyContentService::API_KEY_SETTING, "oa-token", "t", tenant: tenant)
      Setting.set(described_class::MUSE_API_KEY_SETTING, "meta-token", "t", tenant: tenant)

      expect(described_class.find("openai").api_key(tenant: tenant)).to eq("oa-token")
      expect(described_class.find("muse").api_key(tenant: tenant)).to eq("meta-token")
      expect(described_class.find("muse").connected?(tenant: tenant)).to be(true)
    end

    it "voice dedicado cai no token geral do mesmo provedor" do
      Setting.set(described_class::MUSE_API_KEY_SETTING, "meta-token", "t", tenant: tenant)

      muse = described_class.find("muse")
      expect(muse.dedicated_voice_api_key_configured?(tenant: tenant)).to be(false)
      expect(muse.voice_api_key(tenant: tenant)).to eq("meta-token")
    end
  end

  describe ".build_client" do
    it "instancia o cliente do provedor ativo" do
      expect(described_class.build_client(tenant: tenant, api_key: "x")).to be_a(OpenAi::Client)

      Setting.set(described_class::SETTING, "muse", "Provedor", tenant: tenant)
      expect(described_class.build_client(tenant: tenant, api_key: "x")).to be_a(MetaAi::Client)
    end
  end
end
