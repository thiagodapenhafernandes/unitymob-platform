import { Controller } from "@hotwired/stimulus"

// Liga campos de formulário a uma prévia, só com atributos (nenhum JS por tela):
//   data-live-var="--nome"   variável CSS no elemento do controller (data-live-kind="color|number", data-live-unit, data-live-fallback)
//   data-live-text="chave"   texto de [data-live-text-target="chave"]  (vazio volta ao texto original)
//   data-live-attr="modo"    radio/select/checkbox: grava data-<modo> no elemento do controller (checkbox: on/off)
//   data-live-flag="chave"   checkbox: mostra/esconde [data-live-flag-target="chave"]
//   data-live-meter="chave"  campos de --hps-overlay-*: atualiza [data-live-meter-target="chave"] (data-level low|ok|high)
//   data-live-focus="area"   numa seção/painel: destaca [data-live-focus-target="area"] na prévia e rola até ele
//   data-live-fill='{"campo[nome]":"valor"}'  botão (click->live-preview#fill): preenche campos e dispara input
//   data-live-image="url"    botão (click->live-preview#image): troca a imagem [data-live-image-target] da prévia
// O elemento aplica tudo ao conectar (valores salvos) e a cada input/change:
//   <div data-controller="live-preview" data-action="input->live-preview#sync change->live-preview#sync">
// Botões data-live-device="mobile|desktop" + click->live-preview#device alternam data-preview-device.
const CONTROLS = "[data-live-var], [data-live-text], [data-live-attr], [data-live-flag], [data-live-meter]"
const HEX = /^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/i

export default class extends Controller {
  connect() {
    this.element.querySelectorAll("[data-live-text-target]").forEach((el) => {
      if (el.dataset.liveDefault === undefined) el.dataset.liveDefault = el.textContent.trim()
    })
    // O seletor de cor nativo nunca é vazio; o valor salvo (ou herdado) vem do campo de texto.
    this.element.querySelectorAll(CONTROLS).forEach((control) => {
      if (control.type !== "color") this.apply(control)
    })
  }

  sync(event) {
    const control = event.target.closest?.(CONTROLS)
    if (control) this.apply(control)
  }

  apply(control) {
    const data = control.dataset
    if (data.liveVar) this.applyVar(control)
    if (data.liveText) this.applyText(control)
    if (data.liveAttr) this.applyAttr(control)
    if (data.liveFlag) this.applyFlag(control)
    if (data.liveMeter) this.applyMeter(data.liveMeter)
  }

  applyVar(control) {
    const { liveVar, liveKind, liveUnit = "", liveFallback } = control.dataset
    let value = control.value.trim()
    if (liveKind === "color" && !HEX.test(value)) value = ""
    if (liveKind === "number" && !Number.isFinite(Number(value))) value = ""
    if (value === "") value = liveFallback || ""
    if (value === "") this.element.style.removeProperty(liveVar)
    else this.element.style.setProperty(liveVar, `${value}${liveUnit}`)
  }

  applyText(control) {
    const text = control.value.trim()
    this.element.querySelectorAll(`[data-live-text-target="${control.dataset.liveText}"]`).forEach((el) => {
      el.textContent = text || el.dataset.liveDefault || ""
    })
  }

  applyAttr(control) {
    const attr = control.dataset.liveAttr
    if (control.type === "checkbox") this.element.dataset[attr] = control.checked ? "on" : "off"
    else if (control.type !== "radio" || control.checked) this.element.dataset[attr] = control.value
  }

  applyFlag(control) {
    this.element.querySelectorAll(`[data-live-flag-target="${control.dataset.liveFlag}"]`).forEach((el) => {
      el.hidden = !control.checked
    })
  }

  // Sobreposição escura o bastante para o texto branco do hero: pesa opacidade e luminosidade da cor.
  applyMeter(key) {
    const style = this.element.style
    const opacity = Number.parseFloat(style.getPropertyValue("--hps-overlay-opacity")) || 0
    const hex = style.getPropertyValue("--hps-overlay-color").trim()
    const [r, g, b] = HEX.test(hex) ? [1, 3, 5].map((i) => Number.parseInt(hex.slice(i, i + 2), 16) / 255) : [0, 0, 0]
    const score = opacity * (1 - (0.2126 * r + 0.7152 * g + 0.0722 * b))
    const level = score < 0.3 ? "low" : score > 0.6 ? "high" : "ok"
    this.element.querySelectorAll(`[data-live-meter-target="${key}"]`).forEach((meter) => {
      meter.dataset.level = level
      const text = meter.querySelector("[data-meter-text]")
      if (text) text.textContent = meter.dataset[`text${level[0].toUpperCase()}${level.slice(1)}`] || ""
      const bar = meter.querySelector("[data-meter-bar]")
      if (bar) bar.style.setProperty("--meter", `${Math.round(Math.min(score / 0.8, 1) * 100)}%`)
    })
  }

  focus(event) {
    const area = event.target.closest?.("[data-live-focus]")?.dataset.liveFocus
    if (!area || this.element.dataset.focusArea === area) return
    this.element.dataset.focusArea = area
    const target = this.element.querySelector(`[data-live-focus-target="${area}"]`)
    const scroller = target?.closest("[data-live-scroller]")
    if (target && scroller) scroller.scrollTo({ top: Math.max(target.offsetTop - 8, 0), behavior: "smooth" })
  }

  fill(event) {
    const values = JSON.parse(event.currentTarget.dataset.liveFill || "{}")
    Object.entries(values).forEach(([name, value]) => {
      const field = this.element.querySelector(`[name="${name}"]`)
      if (!field) return
      field.value = value
      field.dispatchEvent(new Event("input", { bubbles: true }))
      field.dispatchEvent(new Event("change", { bubbles: true }))
    })
    this.element.querySelectorAll("[data-live-fill]").forEach((button) => button.setAttribute("aria-pressed", String(button === event.currentTarget)))
  }

  image(event) {
    const src = event.currentTarget.dataset.liveImage
    this.element.querySelectorAll("[data-live-image-target]").forEach((img) => { if (src) img.src = src })
    this.element.querySelectorAll("[data-live-image]").forEach((button) => button.setAttribute("aria-pressed", String(button === event.currentTarget)))
  }

  device(event) {
    const device = event.currentTarget.dataset.liveDevice
    this.element.dataset.previewDevice = device
    this.element.querySelectorAll("[data-live-device]").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.liveDevice === device))
    })
  }
}
