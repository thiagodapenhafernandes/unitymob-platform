require "rails_helper"

RSpec.describe Habitations::AuditChangeRecorder do
  it "does not record manual admin noise fields when they change with a real field" do
    habitation = create(:habitation, status: "Venda", agenciador: nil, imovel_dwv: nil, perfil_construcao: "Alto Padrão", tipo_vaga: "Escritura")
    habitation.skip_auto_audit = true
    habitation.update!(status: "Vendido terceiros", agenciador: "", imovel_dwv: "Não", perfil_construcao: "", tipo_vaga: "")

    described_class.new(
      habitation,
      actor: create(:admin_user, :admin),
      source: "admin",
      ignored_fields: described_class::ADMIN_NOISE_FIELDS
    ).record_update!

    log = HabitationAuditLog.where(habitation: habitation).last
    expect(log.changed_fields).to eq(["status"])
    expect(log.changeset).to eq(
      "status" => { "before" => "Venda", "after" => "Vendido terceiros" }
    )
  end

  it "does not record empty equivalent changes" do
    habitation = create(:habitation, face: nil)
    habitation.skip_auto_audit = true
    habitation.update!(face: "")

    expect {
      described_class.new(habitation, actor: nil, source: "admin").record_update!
    }.not_to change(HabitationAuditLog, :count)
  end

  it "does not record phone formatting as a real change" do
    habitation = create(:habitation, proprietario_celular: "47 99987.7770")
    habitation.skip_auto_audit = true
    habitation.update!(proprietario_celular: "(47) 99987-7770")

    expect {
      described_class.new(habitation, actor: nil, source: "admin").record_update!
    }.not_to change(HabitationAuditLog, :count)
  end
end
