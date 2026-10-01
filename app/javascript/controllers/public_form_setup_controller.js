import { Controller } from "@hotwired/stimulus"
import { focusStep, goToStep, renderProgress } from "controllers/ax_guided"

// Nome -> ID (slug) automático em formulário novo, âncora "#modal-<slug>" copiável e
// lateral do modelo Premium visível só quando o modelo não é Básico.
export default class extends Controller {
  static targets = ["name", "slug", "anchor", "example", "copyLabel", "aside", "linkWarning", "linkWarningText"]
  static values = { autoSlug: Boolean }

  connect() {
    const slug = this.slugTarget.value.trim()
    this.auto = this.autoSlugValue && (slug === "" || slug === this.slugify(this.nameTarget.value))
    this.sync()
    this.refreshProgress()
  }

  nameChanged() {
    if (this.auto) this.slugTarget.value = this.slugify(this.nameTarget.value)
    this.sync()
  }

  slugChanged() {
    this.auto = this.slugTarget.value.trim() === ""
    this.sync()
  }

  sync() {
    const anchor = `#modal-${this.slugTarget.value.trim() || "…"}`
    this.anchorTarget.textContent = anchor
    this.exampleTarget.textContent = anchor
    const layout = this.element.querySelector("[name='public_form[modal_layout]']:checked")?.value
    if (layout) this.asideTargets.forEach((element) => { element.hidden = layout === "basic" })
    this.updateLinkWarning(anchor)
  }

  // O link #modal-ID só abre o modal no site com o formulário Publicado e "Disponível para modal" ligado.
  updateLinkWarning(anchor) {
    if (!this.hasLinkWarningTarget) return

    const status = this.element.querySelector("[name='public_form[status]']:checked")?.value
    const enabled = this.element.querySelector("input[type='checkbox'][name='public_form[modal_enabled]']")?.checked
    const names = { draft: "Rascunho", inactive: "Inativo" }
    let message = ""

    if (status && status !== "published") {
      message = `Este formulário está em ${names[status] || status}: o link ${anchor} só abre o modal no site depois de publicar (botão Publicar ou bloco Publicação).`
    } else if (enabled === false) {
      message = "“Disponível para modal” está desligado (bloco Publicação): o link não abre o modal no site."
    }

    this.linkWarningTarget.hidden = message === ""
    this.linkWarningTextTarget.textContent = message
  }

  // O texto principal é só texto formatado: sem anexos/imagens.
  blockFiles(event) {
    event.preventDefault()
  }

  // Depois do primeiro salvamento o ID (slug) não acompanha mais o nome: links já publicados não podem quebrar.
  lockSlug() {
    this.auto = false
  }

  // Cores do modal: seletor nativo <-> campo hex (em branco = padrão do tema).
  pickColor(event) {
    const text = this.colorText(event.currentTarget.dataset.colorPicker)
    if (!text) return

    text.value = event.currentTarget.value
    text.dispatchEvent(new Event("input", { bubbles: true }))
  }

  syncColor(event) {
    const value = event.currentTarget.value.trim()
    const picker = this.element.querySelector(`[data-color-picker='${event.currentTarget.dataset.colorText}']`)
    if (picker && /^#[0-9a-f]{6}$/i.test(value)) picker.value = value
  }

  clearColor(event) {
    const text = this.colorText(event.currentTarget.dataset.colorKey)
    if (!text) return

    text.value = ""
    text.dispatchEvent(new Event("input", { bubbles: true }))
  }

  colorText(key) {
    return this.element.querySelector(`[data-color-text='${key}']`)
  }

  // Progresso e checklist da revisão: nome e título, ao menos um campo e o ID do modal.
  refreshProgress() {
    const value = (name) => this.element.querySelector(`[name='public_form[${name}]']`)?.value.trim()
    const hasTexts = !!value("name") && !!value("title")
    const fields = this.element.querySelectorAll("[data-public-form-builder-target~='field']:not([hidden])").length
    const hasSlug = !!this.slugTarget.value.trim()
    const ready = hasTexts && fields > 0 && hasSlug
    const done = [hasTexts, fields > 0, hasSlug].filter(Boolean).length

    renderProgress(this.element, {
      states: { 1: true, 2: hasTexts, 3: hasSlug, 4: fields > 0, 5: true, 6: true, 7: ready },
      checks: {
        title: [hasTexts, hasTexts ? "Nome e título" : "Preencha o nome e o título"],
        fields: [fields > 0, fields > 0 ? `${fields} campo(s)` : "Adicione ao menos um campo"],
        slug: [hasSlug, hasSlug ? "ID do modal" : "Falta o ID do modal"]
      },
      count: [done, 3],
      label: ready ? "Pronto para salvar" : (!hasTexts ? "Falta o nome e o título" : (fields === 0 ? "Adicione ao menos um campo" : "Falta o ID do modal")),
      ready
    })
  }

  focusStep(event) { focusStep(this.element, event) }

  goToStep(event) { goToStep(this.element, event) }


  async copy() {
    await navigator.clipboard?.writeText(this.anchorTarget.textContent)
    this.copyLabelTarget.textContent = "Copiado"
    setTimeout(() => { this.copyLabelTarget.textContent = "Copiar" }, 1500)
  }

  slugify(value) {
    return value.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
  }
}
