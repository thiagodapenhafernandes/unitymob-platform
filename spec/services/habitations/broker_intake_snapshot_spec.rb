require "rails_helper"

RSpec.describe Habitations::BrokerIntakeSnapshot do
  let(:actor) { create(:admin_user, :admin, name: "Captador Snapshot") }

  it "monta uma fotografia exibível dos dados enviados na captação" do
    habitation = create(
      :habitation,
      :broker_intake,
      admin_user: actor,
      codigo: "SNAP-#{SecureRandom.hex(4)}",
      titulo_anuncio: "Apartamento enviado pelo corretor",
      nome_empreendimento: "Edifício Foto Inicial",
      proprietario: "Maria Proprietária",
      proprietario_celular: "5547999990000",
      valor_venda_cents: 1_230_000_00,
      valor_locacao_cents: 0
    )

    snapshot = described_class.build(
      habitation,
      actor: actor,
      captured_at: Time.zone.local(2026, 7, 31, 10, 30)
    )

    expect(snapshot).to include(
      "version" => described_class::VERSION,
      "property_code" => habitation.codigo,
      "captured_by" => hash_including("name" => "Captador Snapshot")
    )

    identification = snapshot.fetch("sections").find { |section| section["key"] == "identificacao" }
    negotiation = snapshot.fetch("sections").find { |section| section["key"] == "negociacao" }

    expect(identification.fetch("rows")).to include(
      hash_including("label" => "Título do anúncio", "value" => "Apartamento enviado pelo corretor"),
      hash_including("label" => "Empreendimento/Condomínio", "value" => "Edifício Foto Inicial")
    )
    expect(negotiation.fetch("rows")).to include(
      hash_including("label" => "Valor de venda", "value" => "R$ 1.230.000,00")
    )
  end

  it "persiste sem sobrescrever uma fotografia já registrada" do
    habitation = create(:habitation, :broker_intake, admin_user: actor)
    original = described_class.build(habitation, actor: actor)
    replacement = original.deep_dup
    replacement["sections"].first["rows"].first["value"] = "Valor alterado"

    described_class.persist!([habitation], snapshot: original)
    described_class.persist!([habitation.reload], snapshot: replacement)

    expect(habitation.reload.broker_intake_snapshot).to eq(original)
  end
end
