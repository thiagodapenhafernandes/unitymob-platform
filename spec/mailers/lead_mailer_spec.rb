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
  end

  describe "#welcome_lead" do
    it "não monta mensagem SMTP quando o lead não informou e-mail" do
      lead = create(:lead, email: "")

      mail = described_class.with(lead: lead).welcome_lead

      expect(mail.message).to be_a(ActionMailer::Base::NullMail)
    end
  end
end
