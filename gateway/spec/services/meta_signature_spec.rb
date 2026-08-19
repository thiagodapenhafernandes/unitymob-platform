# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gateway::MetaSignature do
  it "validates signatures using the app secret" do
    body = { ok: true }.to_json
    signature = described_class.sign(body, app_secret: "secret")

    expect(described_class.valid?(body, signature, app_secret: "secret")).to be(true)
    expect(described_class.valid?(body, signature, app_secret: "other")).to be(false)
  end
end
