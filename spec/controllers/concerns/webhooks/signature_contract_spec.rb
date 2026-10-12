require "rails_helper"

RSpec.describe Webhooks::MetaSignature do
  it "verifica os bytes originais do contrato Gateway e rejeita adulteração" do
    fixture = JSON.parse(File.read(Rails.root.join("spec/fixtures/contracts/webhook-signatures.json")))
    verifier = Struct.new(:request).new.extend(described_class)
    headers = { described_class::GATEWAY_SIGNATURE_HEADER => fixture.fetch("signature") }
    allow(verifier).to receive(:request).and_return(double(headers: headers))
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_FORWARDING_SECRET").and_return(fixture.fetch("secret"))
    expect(verifier.send(:valid_gateway_signature?, fixture.fetch("body"))).to be(true)
    expect(verifier.send(:valid_gateway_signature?, fixture.fetch("body").strip)).to be(false)
    headers[described_class::GATEWAY_SIGNATURE_HEADER] = "sha256=invalid"
    expect(verifier.send(:valid_gateway_signature?, fixture.fetch("body"))).to be(false)
  end
end
