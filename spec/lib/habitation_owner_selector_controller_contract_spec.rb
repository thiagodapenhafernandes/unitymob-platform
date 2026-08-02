require "rails_helper"

RSpec.describe "habitation owner selector controller" do
  let(:source) { Rails.root.join("app/javascript/controllers/habitation_owner_selector_controller.js").read }

  it "mantém a ação de cadastrar novo proprietário mesmo quando a busca retorna resultados" do
    expect(source).to include("this.updateNoResultsAction(proprietors.length)")
    expect(source).to include('resultCount > 0 ? "Não é nenhum destes?" : "Nenhum proprietário encontrado."')
    expect(source).not_to include("this.noResultsTarget.hidden = proprietors.length > 0")
  end

  it "seleciona proprietário completo direto no modo inline" do
    select_method = source[/select\(event\) \{.*?\n  \}/m]

    expect(select_method).to include("this.needsContactCompletion(payload)")
    expect(select_method).not_to include("this.inlineValue || this.needsContactCompletion(payload)")
    expect(select_method).to include("this.applyProprietor(payload)")
    expect(select_method).to include("this.finishSelection()")
  end
end
