require "rails_helper"

RSpec.describe HabitationAuditLog, type: :model do
  describe "auditoria automática do imóvel" do
    it "registra alterações feitas fora do controller administrativo" do
      habitation = create(:habitation, codigo: "AUTO-AUD-#{SecureRandom.hex(6)}", foto_classificacao: "Aceitáveis")

      expect {
        habitation.update!(foto_classificacao: "Boas")
      }.to change { HabitationAuditLog.where(habitation_id: habitation.id, action: "updated").count }.by(1)

      log = HabitationAuditLog.where(habitation_id: habitation.id, action: "updated").last
      expect(log.changed_fields).to include("foto_classificacao")
      expect(log.source).to eq("integracao")
    end
  end

  describe "#change_summaries" do
    it "formats currency and boolean values in a readable way" do
      log = build(
        :habitation_audit_log,
        changeset: {
          "valor_venda_cents" => { "before" => 900_000_00, "after" => 950_000_00 },
          "valor_vendido_terceiros_cents" => { "before" => nil, "after" => 880_000_00 },
          "motivo_suspensao" => { "before" => "", "after" => "Vendido por outra imobiliária" },
          "exibir_no_site_flag" => { "before" => false, "after" => true }
        }
      )

      summaries = log.change_summaries

      expect(summaries).to include(
        hash_including(label: "Valor de venda", before: "R$ 900.000,00", after: "R$ 950.000,00"),
        hash_including(label: "Valor vendido por terceiros", before: "vazio", after: "R$ 880.000,00"),
        hash_including(label: "Motivo de suspensão", before: "vazio", after: "Vendido por outra imobiliária"),
        hash_including(label: "Publicação no site", before: "Não", after: "Sim")
      )
    end

    it "hides empty no-op and technical noise fields from the timeline" do
      log = build(
        :habitation_audit_log,
        changeset: {
          "status" => { "before" => "Venda", "after" => "Vendido terceiros" },
          "face" => { "before" => nil, "after" => "" },
          "agenciador" => { "before" => nil, "after" => "" },
          "data_atualizacao_crm" => { "before" => "2024-12-17T00:00:00-03:00", "after" => "2026-06-09T16:48:37-03:00" },
          "imovel_dwv" => { "before" => "Não", "after" => "Não" },
          "perfil_construcao" => { "before" => "Alto Padrão", "after" => "" },
          "pictures" => { "before" => ["https://cdn.example/foto.jpg"], "after" => ["https://cdn.example/foto.jpg"] },
          "photo_ids_order" => { "before" => [], "after" => [] },
          "proprietario_celular" => { "before" => "47 99987.7770", "after" => "(47) 99987-7770" },
          "tipo_vaga" => { "before" => "Escritura", "after" => "" }
        }
      )

      summaries = log.change_summaries

      expect(summaries.map { |summary| summary[:field] }).to eq(["status"])
      expect(summaries.first).to include(
        label: "Status comercial",
        before: "Venda",
        after: "Vendido terceiros"
      )
    end
  end

  it "não usa nome de admin_user de outro Tenant no actor_name" do
    tenant = Tenant.create!(name: "Tenant #{SecureRandom.hex(3)}", slug: "tenant-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro #{SecureRandom.hex(3)}", slug: "outro-#{SecureRandom.hex(3)}")
    profile = other_tenant.profiles.find_by!(key: "agent")
    other_user = create(:admin_user, tenant: other_tenant, profile: profile, name: "Usuário Externo")
    habitation = create(:habitation, tenant: tenant)
    log = build(:habitation_audit_log, tenant: tenant, habitation: habitation, admin_user_id: other_user.id)

    expect(log.actor_name).to eq("Sistema")
  end
end
