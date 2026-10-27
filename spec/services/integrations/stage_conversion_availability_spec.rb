require "rails_helper"

RSpec.describe Integrations::StageConversionAvailability do
  let(:tenant) { Tenant.default }
  subject(:availability) { described_class.new(tenant) }

  it "mantém indisponível sem configuração e não aproveita outra conta" do
    other = Tenant.create!(name: "Outra", slug: "availability-other")
    WebhookSetting.create!(tenant: other, webhook_url: "https://gtm.example.test/events")
    expect(availability.state(:google)).to eq(:missing)
    expect(availability.state(:meta)).to eq(:missing)
    expect(availability.state(:unknown)).to eq(:missing)
  end

  it "distingue configuração preparada de ativação Google sem alterar os dados" do
    setting = WebhookSetting.create!(tenant: tenant, webhook_url: "https://gtm.example.test/events", enabled: true)
    expect(availability.state(:google)).to eq(:paused)
    setting.update!(google_conversions_enabled: true)
    expect(availability.state(:google)).to eq(:active)
    setting.update!(enabled: false)
    expect(availability.state(:google)).to eq(:paused)
  end

  it "considera token e datasets Meta e permite preparar com envio pausado" do
    config = MetaConversionConfig.create!(tenant: tenant, enabled: false, datasets: [{"id"=>"123"}])
    expect(availability.state(:meta)).to eq(:missing)
    allow_any_instance_of(MetaConversionConfig).to receive(:sending_token).and_return("test-token")
    expect(availability.state(:meta)).to eq(:paused)
    config.update!(enabled: true)
    expect(availability.state(:meta)).to eq(:active)
  end
end
