require "rails_helper"

RSpec.describe Dashboard::AiDiagnosis do
  describe ".budget_reais_to_cents" do
    { "0" => 0, "10,00" => 1000, "25.50" => 2550, "1.000,00" => 100000 }.each do |input, cents|
      it("converte #{input} sem perda de centavos") { expect(described_class.budget_reais_to_cents(input)).to eq(cents) }
    end
    ["", "abc", "1.000", "-1", "1000,01", "10,001"].each do |input|
      it("rejeita valor inválido #{input.inspect}") { expect { described_class.budget_reais_to_cents(input) }.to raise_error(ArgumentError) }
    end
  end

  let(:tenant) { Tenant.create!(name: "Tenant IA BI #{SecureRandom.hex(3)}", slug: "tenant-ia-bi-#{SecureRandom.hex(3)}") }
  let(:admin) { create(:admin_user, :admin, tenant: tenant) }
  let(:metrics) do
    {
      period_days: 7,
      leads_total: 12,
      no_first_contact_leads: 3,
      pending_whatsapp_conversations: 2,
      property_low_progress_count: 1,
      lost_money_count: 4,
      stage_bottleneck_count: 2,
      site_visits: 40
    }
  end

  it "gera diagnóstico determinístico sem chamar OpenAI quando o BI IA está desligado" do
    allow(OpenAi::Client).to receive(:new)

    result = described_class.new(tenant: tenant, admin_user: admin, period: 7, metrics: metrics).call

    expect(result[:source]).to eq("deterministic")
    expect(result[:ai_enabled]).to eq(false)
    expect(result[:summary]).to include("Principais frentes")
    expect(result[:recommendations].map { |item| item[:title] }).to include("Atender leads sem primeiro contato")
    expect(OpenAi::Client).not_to have_received(:new)
  end

  it "respeita limite semanal e não chama OpenAI quando esgotado" do
    Setting.set(described_class::ENABLED_SETTING, "true", "IA BI", tenant: tenant)
    Setting.set(described_class::WEEKLY_REQUEST_LIMIT_SETTING, "1", "Limite", tenant: tenant)
    OpenAiUsageEvent.create!(tenant: tenant, admin_user: admin, feature: described_class::FEATURE, status: "succeeded", created_at: Time.current)
    Setting.set(Ai::PropertyContentService::API_KEY_SETTING, "token", "Token", tenant: tenant)
    allow(OpenAi::Client).to receive(:new)

    result = described_class.new(tenant: tenant, admin_user: admin, period: 7, metrics: metrics).call

    expect(result[:source]).to eq("deterministic")
    expect(result[:ai_enabled]).to eq(true)
    expect(result.dig(:limit_status, :weekly_remaining)).to eq(0)
    expect(OpenAi::Client).not_to have_received(:new)
  end

  it "chama OpenAI dentro do limite e registra uso estimado" do
    Setting.set(described_class::ENABLED_SETTING, "true", "IA BI", tenant: tenant)
    Setting.set(described_class::WEEKLY_REQUEST_LIMIT_SETTING, "2", "Limite", tenant: tenant)
    Setting.set(described_class::MONTHLY_BUDGET_CENTS_SETTING, "1000", "Teto", tenant: tenant)
    Setting.set(Ai::PropertyContentService::API_KEY_SETTING, "token", "Token", tenant: tenant)
    Setting.set(Ai::PropertyContentService::MODEL_SETTING, "gpt-4.1-mini", "Modelo", tenant: tenant)
    allow(OpenAi::ModelCatalog).to receive(:fallback_response_model).and_return("gpt-4.1-mini")
    client = instance_double(OpenAi::Client)
    allow(OpenAi::Client).to receive(:new).and_return(client)
    allow(client).to receive(:create_response).and_return(
      {
        "output_text" => {
          title: "Diagnóstico da semana",
          summary: "Priorize atendimento e mídia paga.",
          recommendations: [
            { title: "Atender SLA", detail: "Resolver leads sem contato.", value: 3, tone: "red" }
          ],
          rationale: ["3 leads sem contato"]
        }.to_json,
        "usage" => { "input_tokens" => 100, "output_tokens" => 50 }
      }
    )

    result = described_class.new(tenant: tenant, admin_user: admin, period: 7, metrics: metrics).call

    expect(result[:source]).to eq("openai")
    expect(result[:summary]).to eq("Priorize atendimento e mídia paga.")
    usage = OpenAiUsageEvent.find_by!(tenant: tenant, feature: described_class::FEATURE)
    expect(usage.admin_user).to eq(admin)
    expect(usage.input_tokens).to eq(100)
    expect(usage.output_tokens).to eq(50)
    expect(usage.estimated_cost_cents).to be >= 1
  end
end
