require "rails_helper"

RSpec.describe AdminUser, type: :model do
  let(:tenant) { Tenant.default }

  def create_broker(name, broker_tenant: tenant, avatar: true, **attrs)
    profile = Profile.create!(
      tenant: broker_tenant, name: "Corretor #{name} #{SecureRandom.hex(3)}",
      axis: Profile::AXES[:vertical], active: true, position: 1
    )
    broker = AdminUser.create!(
      tenant: broker_tenant, profile: profile, name: name, email: "#{SecureRandom.hex(6)}@broker.test",
      password: "password123", password_confirmation: "password123",
      role: :editor, active: true, display_on_site: true, **attrs
    )
    broker.avatar.attach(io: StringIO.new("foto"), filename: "foto.png", content_type: "image/png") if avatar
    broker
  end

  describe "#site_slug" do
    it "parametriza o nome para a URL" do
      expect(build(:admin_user, name: "Abner Marcelo").site_slug).to eq("abner-marcelo")
    end
  end

  describe ".site_broker_for" do
    it "encontra corretor da vitrine pelo slug" do
      broker = create_broker("Abner Marcelo")

      expect(AdminUser.site_broker_for(tenant, "abner-marcelo")).to eq(broker)
    end

    it "ignora corretor oculto do site" do
      create_broker("Oculto Silva", display_on_site: false)

      expect(AdminUser.site_broker_for(tenant, "oculto-silva")).to be_nil
    end

    it "ignora corretor sem foto (vitrine e página exigem imagem)" do
      broker = create_broker("Sem Foto", avatar: false)

      expect(AdminUser.site_broker_for(tenant, "sem-foto")).to be_nil
      expect(tenant.admin_users.site_brokers).not_to include(broker)
    end

    it "ignora corretor de outra conta" do
      other = Tenant.create!(name: "Outro #{SecureRandom.hex(3)}", slug: "outro-#{SecureRandom.hex(3)}")
      create_broker("Abner Marcelo", broker_tenant: other)

      expect(AdminUser.site_broker_for(tenant, "abner-marcelo")).to be_nil
    end

    it "retorna nil para slug vazio ou inexistente" do
      expect(AdminUser.site_broker_for(tenant, "")).to be_nil
      expect(AdminUser.site_broker_for(tenant, "ninguem-aqui")).to be_nil
    end
  end
end
