require "rails_helper"

RSpec.describe SyncPropertyService do
  around do |example|
    previous_tenant = Current.tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  describe "publication flag preservation" do
    it "preserva exibir_no_site_flag de imóvel existente mesmo sem preservar outros campos manuais" do
      service = described_class.new("9001", preserve_manual_fields: false)

      attrs = service.send(
        :filtered_habitation_attrs,
        {
          titulo_anuncio: "Atualizado pela API",
          exibir_no_site_flag: true,
          destaque_web_flag: true
        },
        existing_record: true
      )

      expect(attrs).to include(titulo_anuncio: "Atualizado pela API", destaque_web_flag: true)
      expect(attrs).not_to have_key(:exibir_no_site_flag)
    end

    it "mantém exibir_no_site_flag da API para imóvel novo" do
      service = described_class.new("9001")

      attrs = service.send(
        :filtered_habitation_attrs,
        { exibir_no_site_flag: true },
        existing_record: false
      )

      expect(attrs).to include(exibir_no_site_flag: true)
    end
  end

  describe "tenant isolation" do
    it "não usa Tenant.default quando não há contexto" do
      Current.tenant = nil
      service = described_class.new("SYNC-NO-TENANT")

      expect(service.perform).to include(success: false, error: "Tenant obrigatório para SyncPropertyService")
    end

    it "resolve corretor do Vista apenas dentro do Tenant corrente" do
      current_tenant = Tenant.create!(name: "Tenant sync #{SecureRandom.hex(3)}", slug: "tenant-sync-#{SecureRandom.hex(3)}")
      other_tenant = Tenant.create!(name: "Outro sync #{SecureRandom.hex(3)}", slug: "outro-sync-#{SecureRandom.hex(3)}")
      current_profile = current_tenant.profiles.find_by!(key: "agent")
      other_profile = other_tenant.profiles.find_by!(key: "agent")
      current_broker = create(:admin_user, tenant: current_tenant, profile: current_profile, vista_id: "BROKER-1")
      create(:admin_user, tenant: other_tenant, profile: other_profile, vista_id: "BROKER-2")

      Current.tenant = current_tenant
      service = described_class.new("SYNC-1")

      expect(service.send(:resolve_broker, { "CodigoCorretor" => "BROKER-1" })).to eq(current_broker.id)
      expect(service.send(:resolve_broker, { "CodigoCorretor" => "BROKER-2" })).to be_nil
    end

    it "resolve proprietario apenas dentro do Tenant corrente" do
      current_tenant = Tenant.create!(name: "Tenant prop #{SecureRandom.hex(3)}", slug: "tenant-prop-#{SecureRandom.hex(3)}")
      other_tenant = Tenant.create!(name: "Outro prop #{SecureRandom.hex(3)}", slug: "outro-prop-#{SecureRandom.hex(3)}")
      other_proprietor = create(:proprietor, tenant: other_tenant, vista_code: "PROP-1", name: "Proprietário Externo")

      Current.tenant = current_tenant
      service = described_class.new("SYNC-2")
      proprietor = service.send(
        :resolve_proprietor,
        { "Proprietario" => "Proprietário Atual", "CodigoProprietario" => "PROP-1" },
        {}
      )

      expect(proprietor).to be_persisted
      expect(proprietor.tenant).to eq(current_tenant)
      expect(proprietor.id).not_to eq(other_proprietor.id)
    end
  end
end
