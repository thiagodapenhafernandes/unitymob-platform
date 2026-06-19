import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["street", "number", "building", "unit", "complement", "category", "commercialStatus", "comparison", "status", "submit"]
  static values = {
    url: String,
    ignoredId: String
  }

  connect() {
    this.timeout = null
    this.hasDuplicate = false
    this.check()
  }

  schedule() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.check(), 350)
  }

  async check() {
    if (!this.identityComplete()) {
      this.hasDuplicate = false
      this.clearStatus()
      this.toggleSubmit(false)
      return
    }

    try {
      const params = new URLSearchParams({
        street: this.streetTarget.value,
        number: this.numberTarget.value,
        building: this.targetValue("building"),
        unit: this.targetValue("unit"),
        complement: this.targetValue("complement"),
        category: this.targetValue("category"),
        status: this.statusValue(),
        comparison: this.comparisonValue()
      })
      if (this.hasIgnoredIdValue && this.ignoredIdValue) params.set("ignored_id", this.ignoredIdValue)

      const response = await fetch(`${this.urlValue}?${params.toString()}`, {
        headers: { "Accept": "application/json" }
      })
      const data = await response.json()
      this.hasDuplicate = Boolean(data.duplicate)

      if (this.hasDuplicate) {
        this.showDuplicate(data.matches || [])
      } else {
        this.showAvailable()
      }
      this.toggleSubmit(false)
    } catch (error) {
      console.error("[habitation-duplicate-check] erro:", error)
      this.clearStatus()
      this.toggleSubmit(false)
    }
  }

  identityComplete() {
    if (!this.hasStreetTarget || !this.hasNumberTarget) return false

    return [this.streetTarget, this.numberTarget].every((target) => target.value.trim().length > 0) &&
      this.statusValue().trim().length > 0 &&
      this.comparisonIdentityComplete()
  }

  comparisonIdentityComplete() {
    if (this.comparisonValue() === "unit") return this.targetValue("unit").trim().length > 0
    if (this.comparisonValue() === "condominium_unit") {
      return this.targetValue("unit").trim().length > 0 || this.targetValue("complement").trim().length > 0
    }

    return true
  }

  statusValue() {
    return this.hasCommercialStatusTarget ? this.commercialStatusTarget.value : ""
  }

  targetValue(name) {
    const targetName = `${name}Target`
    const hasTargetName = `has${name.charAt(0).toUpperCase()}${name.slice(1)}Target`
    return this[hasTargetName] ? this[targetName].value : ""
  }

  comparisonValue() {
    if (this.condominiumHouseSelected() && (this.targetValue("unit").trim().length > 0 || this.targetValue("complement").trim().length > 0)) {
      return "condominium_unit"
    }

    return this.hasComparisonTarget ? this.comparisonTarget.value : ""
  }

  condominiumHouseSelected() {
    return this.targetValue("category").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().includes("casa em condominio")
  }

  showDuplicate(matches) {
    if (!this.hasStatusTarget) return

    this.statusTarget.hidden = false
    this.statusTarget.className = "ax-duplicate-status ax-duplicate-status--danger"
    const links = matches.map((match) => {
      const code = match.codigo ? `#${match.codigo}` : `ID ${match.id}`
      return `<a href="${match.edit_url}" class="ax-duplicate-status__link" target="_blank" rel="noopener">${this.escapeHtml(code)}</a>`
    }).join(", ")
    const identity = this.comparisonValue() === "unit"
      ? "este endereço, unidade e status comercial"
      : (this.comparisonValue() === "condominium_unit" ? "este endereço, complemento, bloco e status comercial" : "este endereço e status comercial")
    this.statusTarget.innerHTML = `Já existe imóvel com ${identity}${links ? `: ${links}` : "."}. Ajuste os dados antes de salvar.`
  }

  showAvailable() {
    // Sem aviso de "tudo certo" — apenas limpa o status.
    // O alerta de duplicata (showDuplicate) continua aparecendo quando houver.
    this.clearStatus()
  }

  clearStatus() {
    if (!this.hasStatusTarget) return
    this.statusTarget.hidden = true
    this.statusTarget.className = "ax-duplicate-status"
    this.statusTarget.textContent = ""
  }

  toggleSubmit(disabled) {
    this.submitTargets.forEach((button) => {
      button.disabled = disabled
      button.classList.toggle("disabled", disabled)
    })
  }

  escapeHtml(value) {
    const div = document.createElement("div")
    div.textContent = value
    return div.innerHTML
  }
}
