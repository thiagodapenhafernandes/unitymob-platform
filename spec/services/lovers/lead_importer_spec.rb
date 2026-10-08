require "rails_helper"

RSpec.describe Lovers::LeadImporter do
  let(:tenant) { Tenant.default }

  it "cria lead Lovers com payload original" do
    result = described_class.call(
      tenant:,
      origin: "Lovers",
      payload: {
        "Code" => 123,
        "Name" => "Cliente Lovers",
        "Email" => "cliente-lovers@example.test",
        "Phone" => "47 99999-3333",
        "Score" => 10,
        "RegistrationDate" => "2026-09-16T10:00:00"
      }
    )

    expect(result).to be_success
    expect(result.status).to eq(:created)
    expect(result.lead.origin).to eq("Lovers")
    expect(result.lead.lead_type).to eq("lovers")
    expect(result.lead.other_information["lovers_code"]).to eq("123")
    expect(result.lead.other_information["lovers_payload"]["Email"]).to eq("cliente-lovers@example.test")
  end

  it "complementa lead existente por e-mail conforme identificação da conta" do
    LeadSetting.instance(tenant: tenant).update!(stickiness_match: "phone_or_email")
    lead = create(:lead, tenant:, name: "Nome original", email: "cliente-lovers@example.test", phone: "47999993333", origin: "Antiga")

    result = described_class.call(
      tenant:,
      origin: "Lovers",
      payload: {
        "Name" => "Cliente Atualizado",
        "Email" => "cliente-lovers@example.test",
        "Phone" => "47 98888-1111"
      }
    )

    expect(result).to be_success
    expect(result.status).to eq(:updated)
    expect(result.lead.id).to eq(lead.id)
    expect(result.lead.reload.name).to eq("Nome original")
    expect(result.lead.origin).to eq("Antiga")
    expect(result.lead.activities.find_by!(kind: "inquiry_complemented").metadata["inquiry_information"]["lovers_payload"]["Name"]).to eq("Cliente Atualizado")
  end
end
