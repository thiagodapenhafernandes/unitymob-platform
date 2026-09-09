import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { categoriesUrl: String }
  static targets = ["categories", "categoryName", "categoryButton", "message"]

  guardUploads(event) {
    if ([...this.element.querySelectorAll("[data-uploading]")].some(el => Number(el.dataset.uploading) > 0)) {
      event.preventDefault()
      this.messageTarget.textContent = "Aguarde o envio dos anexos antes de salvar."
    }
  }

  async createCategory() {
    const name = this.categoryNameTarget.value.trim()
    if (!name) return this.categoryNameTarget.focus()
    this.categoryButtonTarget.disabled = true
    try {
      const response = await fetch(this.categoriesUrlValue, { method: "POST", headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content }, body: JSON.stringify({ blog_category: { name } }) })
      const result = await response.json()
      if (!response.ok) throw new Error(result.error || "Não foi possível criar a categoria.")
      // Reuse the server-rendered shared checkbox, including its accessibility contract.
      this.categoriesTarget.insertAdjacentHTML("beforeend", result.html)
      this.categoryNameTarget.value = ""
      this.messageTarget.textContent = "Categoria criada e selecionada."
    } catch (error) {
      this.messageTarget.textContent = error.message
    } finally {
      this.categoryButtonTarget.disabled = false
    }
  }
}
