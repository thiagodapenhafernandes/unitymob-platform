require "rails_helper"

RSpec.describe "whatsapp integration controller contract" do
  let(:source) { Rails.root.join("app/javascript/controllers/whatsapp_integration_controller.js").read }

  it "solicita dados de sessao v3 no Embedded Signup para receber WABA e telefone" do
    expect(source).to include('sessionInfoVersion: "3"')
    expect(source).to include("parseSessionInfo(data.data)")
    expect(source).to include("trustedMetaOrigin(event.origin)")
  end
end
