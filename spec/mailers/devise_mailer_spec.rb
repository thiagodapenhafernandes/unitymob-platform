require "rails_helper"

RSpec.describe DeviseMailer, "SMTP da conta" do
  before do
    Rails.application.routes.default_url_options[:host] = "localhost"
  end

  around do |example|
    original = ActionMailer::Base.delivery_method
    example.run
    ActionMailer::Base.delivery_method = original
  end

  def configure_smtp!(tenant, **overrides)
    EmailSetting.create!(
      {
        tenant: tenant, enabled: true, smtp_address: "smtp.example.com",
        smtp_port: 587, smtp_user_name: "user", smtp_password: "secret",
        from_email: "contato@example.com", reply_to: "resposta@example.com"
      }.merge(overrides)
    )
  end

  it "descarta o reset quando a conta nao tem SMTP (nao tenta localhost:25)" do
    ActionMailer::Base.delivery_method = :smtp
    user = create(:admin_user)

    mail = described_class.reset_password_instructions(user, "token")

    expect(mail.perform_deliveries).to be(false)
  end

  it "envia pelo SMTP da conta do usuario com o remetente da conta" do
    ActionMailer::Base.delivery_method = :smtp
    user = create(:admin_user)
    configure_smtp!(user.tenant)

    mail = described_class.reset_password_instructions(user, "token")

    expect(mail.perform_deliveries).to be(true)
    expect(mail.delivery_method).to be_a(Mail::SMTP)
    expect(mail.delivery_method.settings[:address]).to eq("smtp.example.com")
    expect(mail.from).to eq(["contato@example.com"])
    expect(mail.reply_to).to eq(["resposta@example.com"])
  end

  it "usa o SMTP da conta do usuario mesmo com outro tenant no contexto" do
    ActionMailer::Base.delivery_method = :smtp
    tenant = Tenant.create!(name: "Conta Devise", slug: "conta-devise-#{SecureRandom.hex(4)}")
    Current.tenant = Tenant.default
    user = create(:admin_user, tenant: tenant)
    configure_smtp!(tenant, smtp_address: "smtp.conta.example.com")

    mail = described_class.reset_password_instructions(user, "token")

    expect(mail.perform_deliveries).to be(true)
    expect(mail.delivery_method.settings[:address]).to eq("smtp.conta.example.com")
  end
end
