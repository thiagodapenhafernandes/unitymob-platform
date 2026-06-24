require "rails_helper"

RSpec.describe Leads::ContactLinks do
  let(:corretor) { create(:admin_user) }
  let(:lead) { create(:lead, admin_user: corretor) }
  let(:setting) { LeadSetting.instance }

  subject(:links) { described_class.new(lead, corretor, setting: setting) }

  describe "#secure?" do
    context "com o master desligado" do
      before { setting.update!(secure_links_enabled: false) }

      it "nenhum canal usa link seguro" do
        expect(links.secure?(:whatsapp)).to be(false)
        expect(links.secure?(:email)).to be(false)
        expect(links.secure?(:push)).to be(false)
      end
    end

    context "com o master ligado" do
      before do
        setting.update!(
          secure_links_enabled: true,
          secure_link_whatsapp: true,
          secure_link_email: false,
          secure_link_push: true
        )
      end

      it "respeita o toggle de cada canal" do
        expect(links.secure?(:whatsapp)).to be(true)
        expect(links.secure?(:email)).to be(false)
        expect(links.secure?(:push)).to be(true)
      end

      it "não usa link seguro para lead não persistido" do
        transient = described_class.new(build(:lead), corretor, setting: setting)
        expect(transient.secure?(:whatsapp)).to be(false)
      end
    end
  end

  describe "#url" do
    it "cria/retorna o /s/:token para a ação, inclusive attend (push)" do
      url = links.url(:attend)
      link = SecureLink.last
      expect(link.action_type).to eq("attend")
      expect(link.lead).to eq(lead)
      expect(link.issued_to_admin_user).to eq(corretor)
      expect(url).to include("/s/#{link.token}")
    end

    it "reaproveita o mesmo link para a mesma ação/corretor" do
      expect { 2.times { links.url(:phone) } }
        .to change(SecureLink, :count).by(1)
    end
  end
end
