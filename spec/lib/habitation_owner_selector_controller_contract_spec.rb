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

  it "abre cadastro novo limpando sugestões e rolando o painel para o mobile" do
    show_create_method = source[/showCreate\(event\) \{.*?\n  \}/m]
    focus_method = source[/focusQuickField\(prefix, panel\) \{.*?\n  \}/m]

    expect(show_create_method).to include("this.prefillCreateFields(this.queryTarget.value.trim())")
    expect(show_create_method).to include("this.hideSearchSuggestions()")
    expect(show_create_method).to include('this.focusQuickField("create", this.createPanelTarget)')
    expect(focus_method).to include("panel?.scrollIntoView")
    expect(focus_method).to include("field?.focus()")
  end

  it "bloqueia o avanço da captação enquanto o proprietário inline não foi salvo" do
    submit_method = source[/handleWizardSubmit\(event\) \{.*?\n  \}/m]

    expect(source).to include('this.form?.addEventListener("submit", this.boundHandleWizardSubmit, true)')
    expect(submit_method).to include("event.preventDefault()")
    expect(submit_method).to include("event.stopImmediatePropagation()")
    expect(submit_method).to include('mode === "create" ? await this.createProprietor() : await this.updateProprietor()')
    expect(submit_method).to include("this.requestWizardSubmit(event.submitter)")
    expect(source).to include('submitter?.name === "direction" && submitter.value === "back"')
  end
end
