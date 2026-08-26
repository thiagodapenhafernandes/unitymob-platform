require "rails_helper"

RSpec.describe Mobile::DeactivateAccountRouteJob, type: :job do
  it "delegates to the registrar with the given email" do
    expect(Mobile::AccountRouteRegistrar).to receive(:deactivate!).with("ex-corretor@salute.test")

    described_class.new.perform("ex-corretor@salute.test")
  end
end
