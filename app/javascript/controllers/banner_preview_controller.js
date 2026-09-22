import { Controller } from "@hotwired/stimulus"

// Prévia do banner como o site o desenha: um por posição, imagem inteira (ou bloco de texto sem imagem), link opcional.
export default class extends Controller {
  static targets = ["stage", "status", "position"]
  static values = { occupancy: Object, labels: Object, savedDesktop: String, savedMobile: String }

  connect() {
    this.deviceMode = "desktop"
    this.urls = {}
    this.refresh()
  }

  disconnect() {
    Object.values(this.urls).forEach((url) => URL.revokeObjectURL(url))
  }

  device(event) {
    this.deviceMode = event.currentTarget.dataset.device
    this.element.querySelectorAll("[data-device]").forEach((button) => button.classList.toggle("is-active", button === event.currentTarget))
    this.refresh()
  }

  // Imagem escolhida agora (arquivo local) tem prioridade sobre a já salva.
  imageFor(kind) {
    const input = this.element.querySelector(`input[type='file'][name='banner[image_${kind}]']`)
    const file = input?.files?.[0]
    if (file) {
      if (this.urls[kind]?.file !== file) {
        if (this.urls[kind]) URL.revokeObjectURL(this.urls[kind].url)
        this.urls[kind] = { file, url: URL.createObjectURL(file) }
      }
      return this.urls[kind].url
    }
    return (kind === "desktop" ? this.savedDesktopValue : this.savedMobileValue) || ""
  }

  value(name) { return this.element.querySelector(`[name='banner[${name}]']`)?.value || "" }

  selectedPositions() {
    return this.positionTargets.filter((input) => input.checked).map((input) => input.value)
  }

  refresh() {
    const positions = this.selectedPositions()
    const first = positions[0]
    const sidebar = first === "sidebar"
    const mobile = this.deviceMode === "mobile" || sidebar
    const desktopImage = this.imageFor("desktop")
    const mobileImage = this.imageFor("mobile")
    const source = mobile ? (mobileImage || desktopImage) : (desktopImage || mobileImage)

    this.stageTarget.replaceChildren(this.mock(first, sidebar, mobile, source))
    this.renderStatus(positions)
  }

  mock(position, sidebar, mobile, source) {
    const frame = this.el("div", `bn-frame ${sidebar ? "bn-frame--sidebar" : (mobile ? "bn-frame--mobile" : "")}`)
    frame.append(this.el("span", "bn-skel bn-skel--wide"), this.el("span", "bn-skel"))

    let banner
    if (source) {
      banner = this.el("div", "bn-banner bn-banner--image")
      const img = document.createElement("img")
      img.src = source
      img.alt = this.value("title")
      banner.append(img)
    } else {
      banner = this.el("div", "bn-banner bn-banner--text")
      banner.append(this.el("strong", "", this.value("title") || "Título do banner"))
      const description = this.value("description")
      if (description) banner.append(this.el("p", "", description))
    }
    if (this.value("link_url")) banner.classList.add("has-link")

    frame.append(banner, this.el("span", "bn-skel"), this.el("span", "bn-skel bn-skel--short"))
    if (!position) frame.append(this.el("p", "bn-frame__empty", "Escolha ao menos uma posição."))
    return frame
  }

  renderStatus(positions) {
    const active = this.element.querySelector("input[type='checkbox'][name='banner[active]']")?.checked !== false
    const order = Number.parseInt(this.value("display_order"), 10) || 0
    const items = []

    if (!active) {
      items.push(["off", "Inativo: não aparece em nenhuma posição."])
    } else if (positions.length === 0) {
      items.push(["warn", "Nenhuma posição escolhida."])
    } else {
      positions.forEach((position) => {
        const label = this.labelsValue[position] || position
        const others = this.occupancyValue[position] || []
        const ahead = others.filter((other) => other.order < order).sort((a, b) => a.order - b.order)[0]
        const tie = others.find((other) => other.order === order)
        if (ahead) items.push(["warn", `${label}: fica atrás de “${ahead.title}” (ordem ${ahead.order}) e não aparece.`])
        else if (tie) items.push(["warn", `${label}: empata com “${tie.title}” (ordem ${tie.order}). Use uma ordem menor para garantir que este apareça.`])
        else items.push(["ok", `${label}: vai aparecer${others.length ? `, na frente de “${others[0].title}”` : ""}.`])
      })
    }

    this.statusTarget.replaceChildren(...items.map(([tone, text]) => this.el("li", `bn-pv__item bn-pv__item--${tone}`, text)))
  }

  el(tag, className, text) {
    const node = document.createElement(tag)
    if (className) node.className = className
    if (text) node.textContent = text
    return node
  }
}
