require "rails_helper"

RSpec.describe Admin::HabitationsController, type: :controller do
  describe "#apply_status_filter" do
    it "hides suspended properties when no status filter is selected" do
      active = create(:habitation, status: "Venda")
      create(:habitation, status: "Suspenso")

      result = controller.send(:apply_status_filter, Habitation.all, nil)

      expect(result).to contain_exactly(active)
    end

    it "shows suspended properties when the suspended status filter is selected" do
      create(:habitation, status: "Venda")
      suspended = create(:habitation, status: "Suspenso")

      result = controller.send(:apply_status_filter, Habitation.all, "Suspenso")

      expect(result).to contain_exactly(suspended)
    end
  end
end
