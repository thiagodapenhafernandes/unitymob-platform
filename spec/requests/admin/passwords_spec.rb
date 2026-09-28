require "rails_helper"

RSpec.describe "Admin::Passwords", type: :request do
  before { host! "localhost" }

  it "mantém a tela de solicitação existente" do
    get new_admin_user_password_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Esqueceu sua senha?")
  end

  it "avisa na tela e nao gera token quando a conta nao tem SMTP" do
    user = create(:admin_user)

    post admin_user_password_path, params: { admin_user: { email: user.email } }

    expect(response).to redirect_to(new_admin_user_password_path)
    expect(flash[:alert]).to match(/indisponível/)
    expect(user.reload.reset_password_token).to be_nil
  end

  it "responde igual para e-mail desconhecido sem SMTP (sem enumeração)" do
    create(:admin_user)

    post admin_user_password_path, params: { admin_user: { email: "ninguem@example.com" } }

    expect(response).to redirect_to(new_admin_user_password_path)
    expect(flash[:alert]).to match(/indisponível/)
  end

  it "envia o reset pelo SMTP da conta quando configurado" do
    user = create(:admin_user)
    EmailSetting.create!(
      tenant: user.tenant, enabled: true, smtp_address: "smtp.example.com",
      smtp_port: 587, smtp_user_name: "user", smtp_password: "secret",
      from_email: "contato@example.com"
    )

    # Devise entrega o reset com deliver_now: o interceptor captura a mensagem
    # e segura o transporte, sem rede.
    messages = []
    interceptor = Module.new do
      define_singleton_method(:delivering_email) do |message|
        messages << message
        message.perform_deliveries = false
      end
    end
    ActionMailer::Base.register_interceptor(interceptor)
    begin
      post admin_user_password_path, params: { admin_user: { email: user.email } }
    ensure
      ActionMailer::Base.unregister_interceptor(interceptor)
    end

    expect(response).to redirect_to(new_admin_user_session_path)
    expect(user.reload.reset_password_token).to be_present
    expect(messages.size).to eq(1)
    expect(messages.first.delivery_method.settings[:address]).to eq("smtp.example.com")
    expect(messages.first.from).to eq(["contato@example.com"])
  end
end
