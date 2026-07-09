require "rails_helper"

RSpec.describe Admin::HabitationsController, type: :controller do
  describe "#permitted_habitation_fields" do
    it "permite salvar parcelamento no cadastro administrativo" do
      fields = controller.send(:permitted_habitation_fields)

      expect(fields).to include(:aceita_parcelamento_flag, :numero_prestacoes)
    end
  end

  describe "#apply_status_filter" do
    it "hides suspended properties when no status filter is selected" do
      active = create(:habitation, status: "Venda")
      suspended = create(:habitation, status: "Suspenso", motivo_suspensao: "Teste")

      result = controller.send(:apply_status_filter, Habitation.where(id: [active.id, suspended.id]), nil)

      expect(result).to contain_exactly(active)
    end

    it "shows suspended properties when the suspended status filter is selected" do
      create(:habitation, status: "Venda")
      suspended = create(:habitation, status: "Suspenso", motivo_suspensao: "Teste")

      result = controller.send(:apply_status_filter, Habitation.where(id: suspended.id), "Suspenso")

      expect(result).to contain_exactly(suspended)
    end
  end
end
