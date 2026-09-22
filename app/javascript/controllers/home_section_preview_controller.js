import { Controller } from "@hotwired/stimulus"

// Formulário de seção da Home: prévia ao vivo com os dados reais da conta.
export default class extends Controller {
  static targets = ["preview"]
  static values = { previewUrl: String }
  static kindLabels = { properties: "Imóveis", property_videos: "Vídeos", developments: "Empreendimentos", blog: "Blog", cta: "Chamada para contato" }

  connect() {
    this.updateManualState()
    this.refresh()
  }

  disconnect() {
    window.clearTimeout(this.timer)
    this.abort?.abort()
  }

  schedule() {
    this.updateCounts()
    window.clearTimeout(this.timer)
    this.timer = window.setTimeout(() => this.refresh(), 350)
  }

  // Com imóveis escolhidos, os filtros automáticos deixam de valer: a tela avisa e os apaga visualmente.
  updateManualState() {
    const picked = this.element.querySelector("select[name$='[selected_property_ids][]']")?.selectedOptions.length || 0
    const filters = this.element.querySelector("[data-hs-filters]")
    if (!filters) return
    filters.classList.toggle("is-ignored", picked > 0)
    const note = filters.querySelector("[data-hs-filters-note]")
    if (note) note.hidden = picked === 0
  }

  updateCounts() {
    this.updateManualState()
    this.element.querySelectorAll("[data-chip-section]").forEach((section) => {
      const inputs = [...section.querySelectorAll(".ax-toggle-chip__input")]
      const counter = section.querySelector("[data-chip-count]")
      if (counter) counter.textContent = `${inputs.filter((input) => input.checked).length}/${inputs.length}`
    })
  }

  async refresh() {
    const form = this.element.querySelector("form")
    if (!form || !this.hasPreviewTarget) return

    this.abort?.abort()
    this.abort = new AbortController()
    const params = new URLSearchParams()
    for (const [key, value] of new FormData(form)) {
      if (key !== "_method" && key !== "authenticity_token" && typeof value === "string") params.append(key, value)
    }
    this.slot("state").textContent = "Atualizando…"

    try {
      const response = await fetch(`${this.previewUrlValue}?${params}`, { headers: { Accept: "application/json" }, signal: this.abort.signal, credentials: "same-origin" })
      if (!response.ok) throw new Error(response.status)
      this.render(await response.json())
    } catch (error) {
      if (error.name !== "AbortError") this.slot("state").textContent = "Prévia indisponível"
    }
  }

  slot(name) { return this.previewTarget.querySelector(`[data-pv='${name}']`) }

  render(data) {
    const state = this.slot("state")
    state.textContent = data.active ? "Visível na Home" : "Oculta da Home"
    state.dataset.state = data.active ? "on" : "off"
    this.slot("kind").textContent = this.constructor.kindLabels[data.kind] || "Seção"

    const title = this.slot("title")
    title.textContent = data.title || "Título da seção"
    title.classList.toggle("is-placeholder", !data.title)
    const subtitle = this.slot("subtitle")
    subtitle.textContent = data.subtitle
    subtitle.hidden = !data.subtitle

    this.slot("body").replaceChildren(...this.bodyFor(data))

    const cta = this.slot("cta")
    cta.textContent = data.cta_label || ""
    cta.hidden = !data.cta_label

    const note = this.slot("note")
    const notes = []
    if (data.warning) notes.push(data.warning)
    else if (data.manual > 0) {
      notes.push(`Só os ${data.manual} imóvel(is) escolhido(s) aparecem; os filtros são ignorados.`)
    } else if (data.kind === "properties" || data.kind === "property_videos" || data.kind === "developments") {
      notes.push(`${data.count} de até ${data.limit} vagas na Home` + (data.matching > data.count ? ` · ${data.matching} atendem aos filtros` : ""))
    }
    if (data.corporate != null) notes.push(`Vitrine corporate: ${data.corporate} imóvel(is)`)
    note.textContent = notes.join(" — ")
    note.hidden = notes.length === 0
    note.dataset.tone = data.warning ? "warning" : "info"
  }

  bodyFor(data) {
    if (data.kind === "cta") return [this.row(data.buttons.map((label) => this.el("span", "hs-pv__btn", label)))]
    if (data.kind === "blog") return data.items.map((item) => this.row([this.el("strong", "", item.title), this.el("small", "", item.meta || "")]))
    const cards = data.items.map((item) => {
      const card = this.el("article", "hs-pv__card")
      const photo = this.el("div", "hs-pv__photo")
      if (item.photo) { const img = document.createElement("img"); img.src = item.photo; img.alt = ""; img.loading = "lazy"; photo.append(img) }
      card.append(photo, this.el("strong", "", item.price), this.el("span", "", item.title), this.el("small", "", item.location))
      return card
    })
    return cards.length ? [this.el("div", "hs-pv__grid", null, cards)] : []
  }

  row(children) { return this.el("div", "hs-pv__row", null, children) }

  el(tag, className, text, children = []) {
    const node = document.createElement(tag)
    if (className) node.className = className
    if (text) node.textContent = text
    node.append(...children)
    return node
  }
}
