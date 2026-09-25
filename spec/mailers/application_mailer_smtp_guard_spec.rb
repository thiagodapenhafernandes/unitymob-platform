require "rails_helper"

RSpec.describe ApplicationMailer, "trava de SMTP" do
  before do
    Rails.application.routes.default_url_options[:host] = "localhost"
  end

  around do |example|
    original = ActionMailer::Base.delivery_method
    example.run
    ActionMailer::Base.delivery_method = original
  end

  it "descarta o envio quando nao ha SMTP configurado e o ambiente usa :smtp" do
    ActionMailer::Base.delivery_method = :smtp
    lead = create(:lead, name: "Sem SMTP", email: "lead@example.com")

    mail = LeadMailer.with(lead: lead).welcome_lead

    expect(mail.perform_deliveries).to be(false)
  end

  it "envia normalmente quando o SMTP da conta esta configurado" do
    ActionMailer::Base.delivery_method = :smtp
    lead = create(:lead, name: "Com SMTP", email: "lead@example.com")
    EmailSetting.create!(
      tenant: lead.tenant, enabled: true, smtp_address: "smtp.example.com",
      smtp_port: 587, smtp_user_name: "user", smtp_password: "secret",
      from_email: "contato@example.com"
    )

    mail = LeadMailer.with(lead: lead).welcome_lead

    expect(mail.perform_deliveries).to be(true)
    expect(mail.delivery_method).to be_a(Mail::SMTP)
    expect(mail.delivery_method.settings[:address]).to eq("smtp.example.com")
  end
end
