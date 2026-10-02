require "rails_helper"

RSpec.describe MetaConversionConfig, type: :model do
  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }

  it "resolve instância por conta mesmo sem registro" do
    config = described_class.instance(tenant: tenant)

    expect(config).to be_new_record
    expect(config.tenant).to eq(tenant)
  end

  it "exige ao menos um dataset e conta única" do
    described_class.create!(tenant: tenant, datasets: [{ "id" => "123", "name" => "Loja" }])

    expect(described_class.new(tenant: tenant)).not_to be_valid
    expect(described_class.new(tenant: tenant, datasets: [])).not_to be_valid
    expect(described_class.new(datasets: [{ "id" => "123" }])).not_to be_valid
    expect(described_class.new(tenant: tenant, datasets: [{ "id" => "456" }])).not_to be_valid
  end

  it "normaliza a lista de datasets" do
    config = described_class.new(tenant: tenant, datasets: [{ "id" => "1", "name" => "A" }, { "id" => "1" }, { "id" => "" }, { id: "2" }])

    expect(config.dataset_list).to eq([{ "id" => "1", "name" => "A" }, { "id" => "2", "name" => "2" }])
  end

  it "usa o token da conexão Meta existente, preferindo não expirado" do
    expired = create(:user_meta_integration, admin_user: admin, tenant: tenant,
                                             access_token: "expirado", token_expires_at: 1.day.ago)
    fresh = create(:user_meta_integration, admin_user: create(:admin_user, tenant: tenant),
                                           tenant: tenant, access_token: "valido",
                                           token_expires_at: 1.day.from_now)
    config = described_class.create!(tenant: tenant, datasets: [{ "id" => "123" }])

    expect(expired).to be_expired
    expect(fresh).not_to be_expired
    expect(config.sending_token).to eq("valido")
    expect(config.active?).to be(true)
  end

  it "fica inativa sem dataset, sem token ou com envio desligado" do
    config = described_class.new(tenant: tenant, datasets: [{ "id" => "123" }])

    expect(config.active?).to be(false)

    create(:user_meta_integration, admin_user: admin, tenant: tenant, access_token: "tok")
    expect(config.active?).to be(true)

    config.enabled = false
    expect(config.active?).to be(false)
  end

  it "não usa token de outra conta" do
    other_tenant = Tenant.create!(name: "Outra #{SecureRandom.hex(3)}", slug: "outra-#{SecureRandom.hex(3)}")
    other_admin = create(:admin_user, tenant: other_tenant)
    create(:user_meta_integration, admin_user: other_admin, tenant: other_tenant, access_token: "outro")
    config = described_class.new(tenant: tenant, datasets: [{ "id" => "123" }])

    expect(config.sending_token).to be_nil
    expect(config.active?).to be(false)
  end
end
