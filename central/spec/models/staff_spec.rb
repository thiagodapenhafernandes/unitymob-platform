require 'rails_helper'
RSpec.describe Staff do
  it 'ativa com token temporário, guarda segredo criptografado e rejeita replay TOTP' do
    staff = Staff.create!(name: 'Ana', email: 'ana@example.test', role: 'suporte')
    token = staff.activation_token!
    expect(staff.activation_digest).to eq(Digest::SHA256.hexdigest(token))
    expect(staff.otp_secret).not_to eq(staff.otp_secret_before_type_cast)
    code = ROTP::TOTP.new(staff.otp_secret).now
    expect(staff.verify_otp!(code)).to be(true)
    expect(staff.verify_otp!(code)).to be(false)
  end
end
