require "rails_helper"

RSpec.describe Admin::HabitationsController, type: :controller do
  describe "#permitted_habitation_fields" do
    it "permite salvar parcelamento no cadastro administrativo" do
      fields = controller.send(:permitted_habitation_fields)

      expect(fields).to include(:aceita_parcelamento_flag, :numero_prestacoes)
    end
  end

  describe "#apply_status_filter" do
    it "shows only active commercial statuses when no status filter is selected" do
      active = create(:habitation, status: "Venda")
      rental = create(:habitation, status: "Aluguel")
      daily = create(:habitation, status: "Diária")
      pending = create(:habitation, status: "Pendente")
      suspended = create(:habitation, status: "Suspenso", motivo_suspensao: "Teste")

      result = controller.send(:apply_status_filter, Habitation.where(id: [active.id, rental.id, daily.id, pending.id, suspended.id]), nil)

      expect(result).to contain_exactly(active, rental, daily)
    end

    it "shows suspended properties when the suspended status filter is selected" do
      create(:habitation, status: "Venda")
      suspended = create(:habitation, status: "Suspenso", motivo_suspensao: "Teste")

      result = controller.send(:apply_status_filter, Habitation.where(id: suspended.id), "Suspenso")

      expect(result).to contain_exactly(suspended)
    end
  end

  describe "default catalog sort" do
    it "uses the newest numeric code by default" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new)

      expect(controller.send(:sort_column)).to eq(described_class::DEFAULT_CODIGO_SORT_SQL)
      expect(controller.send(:sort_direction)).to eq("desc")
    end
  end
end
