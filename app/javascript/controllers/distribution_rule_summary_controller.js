import { Controller } from "@hotwired/stimulus"

// Resumo da regra ao vivo (somente leitura do DOM, sem endpoint/estado servidor).
// Observa origens, modo, fila de corretores e canais, e re-renderiza a frase +
// chips de estado. Também mantém o contador "N na fila" no head da Equipe.
export default class extends Controller {
  static targets = ["line", "chips", "agentCount"]

  connect() {
    this.render = this.render.bind(this)
    // input/change borbulham do form inteiro (toggles, selects, radios)
    this.element.addEventListener("input", this.render)
    this.element.addEventListener("change", this.render)
    // fila muda via JS (add/remove/restore) sem disparar change → observa o DOM
    const list = this.element.querySelector('[data-team-rules-target="list"]')
    if (list) {
      this.observer = new MutationObserver(this.render)
      this.observer.observe(list, { childList: true, subtree: true, attributes: true, attributeFilter: ["style", "value"] })
    }
    this.render()
  }

  disconnect() {
    this.element.removeEventListener("input", this.render)
    this.element.removeEventListener("change", this.render)
    this.observer?.disconnect()
  }

  // ---- leitura de estado ----
  checked(attr) {
    const el = this.element.querySelector(`input[type=checkbox][name="distribution_rule[${attr}]"]`)
    return Boolean(el && el.checked)
  }

  mode() {
    const el = this.element.querySelector('input[name="distribution_rule[distribution_mode]"]:checked')
    return el ? el.value : "rotary"
  }

  agentCount() {
    const items = this.element.querySelectorAll('[data-team-rules-target="item"]')
    let count = 0
    items.forEach((item) => {
      if (item.style.display === "none") return
      const destroy = item.querySelector('input[name*="[_destroy]"]')
      if (destroy && destroy.value === "1") return
      count += 1
    })
    return count
  }

  // ---- render ----
  render() {
    const modeLabels = {
      rotary: "fila rotativa",
      performance: "sorteio por performance",
      shark_tank: "shark tank (primeiro a aceitar)"
    }
    const sources = []
    if (this.checked("source_meta")) sources.push("Meta Ads")
    if (this.checked("source_webhook")) sources.push("Webhooks")
    if (this.checked("source_site")) sources.push("Site")
    if (this.checked("source_portal")) sources.push("Portais")

    const n = this.agentCount()
    if (this.hasAgentCountTarget) this.agentCountTarget.textContent = String(n)

    if (this.hasLineTarget) {
      const src = sources.length ? `<b>${sources.join(", ")}</b>` : "<b>nenhuma origem</b>"
      const who = n ? `<b>${n} corretor${n > 1 ? "es" : ""}</b>` : "<b>sem corretores</b>"
      this.lineTarget.innerHTML = `Leads de ${src} → ${who} em <b>${modeLabels[this.mode()] || this.mode()}</b>.`
    }

    if (this.hasChipsTarget) {
      const chips = [
        ["whatsapp", "WhatsApp", this.checked("notify_whatsapp")],
        ["clock-history", this.checked("represamento_active") ? "Bolsão ativo" : "Sem bolsão", this.checked("represamento_active")],
        ["hourglass-split", this.checked("pocket_active") ? "Pocket" : "Sem tempo limite", this.checked("pocket_active")]
      ]
      this.chipsTarget.innerHTML = chips.map(([icon, text, on]) =>
        `<span class="ax-badge ${on ? "ax-badge--green" : "ax-badge--gray"} distribution-rule-summary-chip${on ? "" : " is-off"}"><i class="bi bi-${icon}" aria-hidden="true"></i> ${text}</span>`
      ).join("")
    }
  }
}
