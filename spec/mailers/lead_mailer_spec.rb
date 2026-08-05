require "rails_helper"

RSpec.describe LeadMailer, type: :mailer do
  before do
    Rails.application.routes.default_url_options[:host] = "localhost"
  end

  describe "#new_lead_notification" do
    it "monta link de WhatsApp com telefone canônico sem duplicar DDI" do
      lead = create(:lead, name: "Lead Telefone", phone: "47 9972-9441", email: "lead@example.com")

      mail = described_class.with(lead: lead).new_lead_notification
      body = mail.html_part.body.decoded

      expect(body).to include("https://wa.me/5547999729441")
      expect(body).not_to include("https://wa.me/555547999729441")
    end

    it "não usa imóvel nem branding de outro tenant" do
      tenant = Tenant.create!(name: "Conexão Mailer", slug: "conexao-mailer-#{SecureRandom.hex(3)}", active: true)
      other_tenant = Tenant.create!(name: "Salute Mailer", slug: "salute-mailer-#{SecureRandom.hex(3)}", active: true)
      LayoutSetting.instance(tenant: tenant).update!(site_name: "Conexão Imobiliária")
      ContactSetting.instance(tenant: tenant).update!(email_primary: "contato@conexao.test")
      foreign_property = create(:habitation, tenant: other_tenant, titulo_anuncio: "Imóvel Salute")
      lead = create(:lead, tenant: tenant, name: "Lead Conexão", phone: "47 99999-1111")
      lead.update_column(:property_id, foreign_property.id)

      mail = described_class.with(lead: lead).new_lead_notification
      body = mail.html_part.body.decoded

      expect(mail.subject).to include("Conexão Imobiliária")
      expect(mail.to).to eq(["contato@conexao.test"])
      expect(body).not_to include("Imóvel Salute")
    end
  end

  describe "#welcome_lead" do
    it "não monta mensagem SMTP quando o lead não informou e-mail" do
      lead = create(:lead, email: "")

      mail = described_class.with(lead: lead).welcome_lead

      expect(mail.message).to be_a(ActionMailer::Base::NullMail)
    end
  end
end
