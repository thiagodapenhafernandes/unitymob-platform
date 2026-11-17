import { Controller } from "@hotwired/stimulus"

// Form de usuário: reage ao Perfil de acesso e à Área de atuação.
// - Perfil HORIZONTAL → esconde atuação/gestores/exibição no site.
// - Área Venda → só Gestor de Venda; Locação → só de Locação; Ambos → os dois.
export default class extends Controller {
  static targets = ["accessSelect", "actingSelect", "verticalOnly", "salesManagerField", "rentalsManagerField", "managerSelect"]

  connect() {
    this.managerOptions ||= new Map(this.managerSelectTargets.map((select) => [select, Array.from(select.options)]))
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

    this.syncManagers(option)

    const acting = this.hasActingSelectTarget ? this.actingSelectTarget.value : ""
    this.toggleManagerField(this.salesManagerFieldTargets, acting === "sales" || acting === "both" || acting === "")
    this.toggleManagerField(this.rentalsManagerFieldTargets, acting === "rentals" || acting === "both")
  }

  syncManagers(profileOption) {
    this.managerSelectTargets.forEach((select) => {
      const position = profileOption?.dataset?.position || select.dataset.profilePosition
      const selected = select.value
      const options = this.managerOptions.get(select).filter((option) =>
        !option.value || !position || !option.dataset.position || Number(option.dataset.position) < Number(position)
      )
      select.replaceChildren(...options)
      select.value = options.some((option) => option.value === selected) ? selected : ""
    })
  }

  toggleManagerField(targets, visible) {
    targets.forEach((el) => {
      el.hidden = !visible
      if (!visible) el.querySelectorAll("select").forEach((select) => { select.value = "" })
    })
  }
}
