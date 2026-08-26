require "rails_helper"

RSpec.describe Mobile::SyncAccountRouteJob, type: :job do
  it "loads the admin_user and delegates to the registrar" do
    admin_user = create(:admin_user, email: "corretor-#{SecureRandom.hex(4)}@salute.test")
    expect(Mobile::AccountRouteRegistrar).to receive(:sync!).with(admin_user)

    described_class.new.perform(admin_user.id)
  end

  it "does nothing when the admin_user no longer exists" do
    expect(Mobile::AccountRouteRegistrar).not_to receive(:sync!)

    described_class.new.perform(-1)
  end
end
