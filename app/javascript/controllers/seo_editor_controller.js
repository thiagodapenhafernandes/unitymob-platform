import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.update = this.update.bind(this)
    this.element.querySelectorAll("[data-seo-field]").forEach((input) => {
      input.addEventListener("input", this.update)
      input.addEventListener("change", this.update)
    })
    this.update()
  }

  disconnect() {
    this.element.querySelectorAll("[data-seo-field]").forEach((input) => {
      input.removeEventListener("input", this.update)
      input.removeEventListener("change", this.update)
    })
  }

  update() {
    const title = this.text("title")
    const description = this.text("description")
    const keywords = this.text("keywords").split(",").map((item) => item.trim()).filter(Boolean)
    const persistedKeywords = this.text("focusKeywords").split(",").map((item) => item.trim()).filter(Boolean)
    const focus = persistedKeywords[0] || keywords[0] || ""
    const canonical = this.text("canonical")
    const intro = this.text("intro")
    const listing = this.field("intro")?.dataset.listing === "true"

    this.setText(this.counter("title"), title.length)
    this.setText(this.counter("description"), description.length)
    this.setText(this.counter("intro"), this.words(intro))

    this.setText(this.preview("title"), title || "Título da página")
    this.setText(this.preview("description"), description || "Descrição que aparecerá nos resultados de busca.")
    this.setText(this.preview("ogTitle"), this.text("ogTitle") || title || "Título social")
    this.setText(this.preview("ogDescription"), this.text("ogDescription") || description || "Descrição social.")

    this.setCheck("title", title.length >= 35 && title.length <= 65)
    this.setCheck("description", description.length >= 110 && description.length <= 165)
    this.setCheck("keyword", focus.length > 0 && `${title} ${description}`.toLowerCase().includes(focus.toLowerCase()))
    this.setCheck("canonical", canonical.length > 0)
    this.setCheck("intro", !listing || this.words(intro) >= 80)
    this.setCheck("index", this.field("active")?.checked && this.field("apply_to_public")?.checked && this.field("robots_index")?.checked)
  }

  field(name) {
    return this.element.querySelector(`[data-seo-field="${name}"]`)
  }

  preview(name) {
    return this.element.querySelector(`[data-seo-preview="${name}"]`)
  }

  counter(name) {
    return this.element.querySelector(`[data-seo-count="${name}"]`)
  }

  check(name) {
    return this.element.querySelector(`[data-seo-check="${name}"]`)
  }

  text(name) {
    return (this.field(name)?.value || "").trim()
  }

  words(value) {
    return (value.match(/\S+/g) || []).length
  }

  setText(element, value) {
    if (element) element.textContent = value
  }

  setCheck(name, ok) {
    const item = this.check(name)
    if (!item) return
    item.classList.toggle("is-ok", ok)
    item.classList.toggle("is-warning", !ok)
  }
}
