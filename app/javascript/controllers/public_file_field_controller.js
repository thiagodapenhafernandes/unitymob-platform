import { Controller } from "@hotwired/stimulus"

// Campo de anexo do modal público: área de clique/arraste, lista dos arquivos escolhidos e aviso na hora.
// O <input type="file"> continua sendo a fonte do envio; aqui só apresentamos e validamos.
export default class extends Controller {
  static targets = ["input", "drop", "list", "error"]
  static values = { maxMb: Number, maxFiles: Number, accept: String }

  connect() {
    this.form = this.element.closest("form")
    this.onReset = () => setTimeout(() => this.render())
    this.form?.addEventListener("reset", this.onReset)
    this.render()
  }

  disconnect() {
    this.form?.removeEventListener("reset", this.onReset)
  }

  dragOver(event) {
    event.preventDefault()
    this.dropTarget.classList.add("is-over")
  }

  dragLeave() {
    this.dropTarget.classList.remove("is-over")
  }

  drop(event) {
    event.preventDefault()
    this.dropTarget.classList.remove("is-over")
    this.setFiles(Array.from(event.dataTransfer.files))
  }

  changed() {
    this.render()
  }

  remove(event) {
    const index = Number(event.currentTarget.dataset.index)
    this.setFiles(Array.from(this.inputTarget.files).filter((_file, position) => position !== index))
  }

  setFiles(files) {
    const transfer = new DataTransfer()
    files.slice(0, this.maxFilesValue || 1).forEach((file) => transfer.items.add(file))
    this.inputTarget.files = transfer.files
    this.render()
  }

  render() {
    const files = Array.from(this.inputTarget.files || [])
    const allowed = this.acceptValue.split(",").filter(Boolean)
    const maxBytes = this.maxMbValue * 1024 * 1024
    const problems = []

    this.listTarget.replaceChildren(...files.map((file, index) => {
      const extension = `.${file.name.split(".").pop().toLowerCase()}`
      let problem = null
      if (allowed.length && !allowed.includes(extension)) problem = `${file.name}: tipo não permitido.`
      else if (file.size > maxBytes) problem = `${file.name}: passa do limite de ${this.maxMbValue} MB.`
      if (problem) problems.push(problem)
      return this.item(file, index, problem)
    }))

    this.listTarget.hidden = files.length === 0
    this.dropTarget.classList.toggle("has-files", files.length > 0)
    this.errorTarget.textContent = problems.join(" ")
    this.errorTarget.hidden = problems.length === 0
    // Arquivo inválido impede o envio do formulário com a mensagem do navegador.
    this.inputTarget.setCustomValidity(problems[0] || "")
  }

  item(file, index, problem) {
    const item = document.createElement("li")
    item.className = `public-file__item${problem ? " is-invalid" : ""}`

    const icon = document.createElement("i")
    icon.className = `bi ${file.type.startsWith("image/") ? "bi-file-earmark-image" : "bi-file-earmark-text"}`
    icon.setAttribute("aria-hidden", "true")

    const name = document.createElement("span")
    name.className = "public-file__name"
    name.textContent = file.name

    const size = document.createElement("span")
    size.className = "public-file__size"
    size.textContent = this.formatSize(file.size)

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "public-file__remove"
    remove.dataset.index = index
    remove.dataset.action = "public-file-field#remove"
    remove.setAttribute("aria-label", `Remover ${file.name}`)
    remove.innerHTML = '<i class="bi bi-x-lg" aria-hidden="true"></i>'

    item.append(icon, name, size, remove)
    return item
  }

  formatSize(bytes) {
    if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`
    return `${(bytes / (1024 * 1024)).toFixed(1).replace(".", ",")} MB`
  }
}
