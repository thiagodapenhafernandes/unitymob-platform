import { Controller } from "@hotwired/stimulus"

// Prévia do resultado do Google (título, URL e descrição) e contadores, a partir dos campos do formulário.
export default class extends Controller {
  static targets = ["title", "url", "description", "titleCount", "descriptionCount"]
  static values = { host: String }

  connect() {
    this.refresh()
  }

  refresh() {
    const pageTitle = this.value("title")
    const metaTitle = this.value("meta_title")
    const metaDescription = this.value("meta_description")
    const slug = this.value("slug") || this.slugify(pageTitle)

    this.titleTarget.textContent = metaTitle || pageTitle || "Título da página"
    this.urlTarget.textContent = `${this.hostValue}/${slug}`
    this.descriptionTarget.textContent = metaDescription || "Sem descrição: o Google escolhe um trecho da página."
    this.descriptionTarget.classList.toggle("is-empty", !metaDescription)
    this.count(this.titleCountTarget, metaTitle.length, 60)
    this.count(this.descriptionCountTarget, metaDescription.length, 160)
  }

  count(target, length, max) {
    target.textContent = length
    target.parentElement?.classList.toggle("is-over", length > max)
  }

  value(name) {
    return (this.element.querySelector(`[name='landing_page[${name}]']`)?.value || "").trim()
  }

  slugify(text) {
    return text.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
  }
}
