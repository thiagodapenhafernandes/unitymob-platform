import { Controller } from "@hotwired/stimulus"

// Form de usuário: reage ao Perfil de acesso e à Área de atuação.
// - Perfil HORIZONTAL → esconde atuação/gestores/exibição no site.
// - Área Venda → só Gestor de Venda; Locação → só de Locação; Ambos → os dois.
export default class extends Controller {
  static targets = ["accessSelect", "actingSelect", "verticalOnly", "salesManagerField", "rentalsManagerField"]

  connect() {
    this.sync()
  }

  sync() {
    const option = this.hasAccessSelectTarget ? this.accessSelectTarget.selectedOptions[0] : null
    const horizontal = option?.dataset?.axis === "horizontal"

    this.verticalOnlyTargets.forEach((el) => {
      el.hidden = horizontal
      if (horizontal) el.querySelectorAll("select").forEach((select) => { select.value = "" })
    })

    if (horizontal) return

    const acting = this.hasActingSelectTarget ? this.actingSelectTarget.value : ""
    this.toggleManagerField(this.salesManagerFieldTargets, acting === "sales" || acting === "both" || acting === "")
    this.toggleManagerField(this.rentalsManagerFieldTargets, acting === "rentals" || acting === "both")
  }

  toggleManagerField(targets, visible) {
    targets.forEach((el) => {
      el.hidden = !visible
      if (!visible) el.querySelectorAll("select").forEach((select) => { select.value = "" })
    })
  }
}
