require "rspec"
require "json"
require_relative "../../app/services/internal_signature"
require_relative "../../app/services/meta_signature"

RSpec.describe "Contrato compartilhado de assinatura" do
  it "assina e verifica os mesmos bytes, preservando espaços e Unicode" do
    fixture = JSON.parse(File.read(File.expand_path("../../../spec/fixtures/contracts/webhook-signatures.json", __dir__)))
    expect(Gateway::InternalSignature.sign(fixture.fetch("body"), secret: fixture.fetch("secret"))).to eq(fixture.fetch("signature"))
    expect(Gateway::MetaSignature.valid?(fixture.fetch("body"), fixture.fetch("signature"), app_secret: fixture.fetch("secret"))).to be(true)
    expect(Gateway::MetaSignature.valid?(fixture.fetch("body").strip, fixture.fetch("signature"), app_secret: fixture.fetch("secret"))).to be(false)
  end
end
