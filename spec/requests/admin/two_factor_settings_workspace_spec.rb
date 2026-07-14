require "rails_helper"

RSpec.describe "Admin::TwoFactorSettings workspace", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "two-factor-#{SecureRandom.hex(5)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza ativacao e conclui o provisionamento com componentes compartilhados" do
    get admin_two_factor_settings_path

    expect(response).to have_http_status(:ok)
    setup = Nokogiri::HTML(response.body)
    secret = setup.at_css("code.two-factor-secret").text
    expect(secret).to be_present
    expect(setup.at_css('.ax-field input[name="otp_code"]#confirm_otp')).to be_present
    expect(setup.at_css("#confirm_otp").ancestors(".ax-input-group")).to be_present
    expect(setup.at_css(".two-factor-qr svg")).to be_present

    post admin_two_factor_settings_path, params: { otp_code: ROTP::TOTP.new(secret).now }

    expect(response).to have_http_status(:ok)
    backup = Nokogiri::HTML(response.body)
    expect(backup.css("code.two-factor-backup-code").size).to eq(10)
    expect(backup.at_css('[data-controller="clipboard"]')).to be_present
    expect(admin.reload).to be_otp_enabled
  end

  it "usa campos compartilhados para regenerar codigos e desativar a protecao" do
    admin.update!(otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)

    get admin_two_factor_settings_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('input[name="otp_code"]#regen_otp')).to be_present
    expect(document.at_css('input[type="password"][name="current_password"]#disable_pwd')).to be_present
    expect(document.css(".ax-input-group").size).to be >= 2
    expect(response.body).to include("Duas etapas ativas", "Gerar novos códigos de backup", "Desativar duas etapas")
  end
end
