import { Controller } from "@hotwired/stimulus"

// Editor de benefícios (lateral do modal): cada linha é um benefício com ícone, texto, remover e arrastar.
// Fonte única: um input oculto com JSON [{ icon, text }]. Vários editores podem apontar para o mesmo input
// (bloco da tela e painel do preview): quem escreve avisa por "input" e os outros recarregam.
export default class extends Controller {
  static targets = ["list"]
  static values = { input: String, icons: Object, defaultIcon: String }

  connect() {
    this.input = document.querySelector(this.inputValue)
    if (!this.input) return

    this.onExternal = () => {
      if (this.input.value !== this.written) this.load()
    }
    this.input.addEventListener("input", this.onExternal)
    this.load()
  }

  disconnect() {
    this.input?.removeEventListener("input", this.onExternal)
  }

  load() {
    this.written = this.input.value
    let items = []
    try {
      items = JSON.parse(this.input.value || "[]")
    } catch (_error) {
      items = []
    }
    this.listTarget.replaceChildren(...items.map((item) => this.row(item)))
  }

  add() {
    const row = this.row({ icon: this.defaultIconValue, text: "" })
    this.listTarget.append(row)
    row.querySelector("input[type='text']").focus()
    this.write()
  }

  write() {
    const items = Array.from(this.listTarget.children).map((row) => ({ icon: row.dataset.icon, text: row.querySelector("input[type='text']").value }))
    const json = JSON.stringify(items)
    this.written = json
    this.input.value = json
    this.input.dispatchEvent(new Event("input", { bubbles: true }))
  }

  row(item) {
    const row = document.createElement("li")
    row.className = "benefits-editor__row"
    row.dataset.icon = this.icons()[item.icon] ? item.icon : this.defaultIconValue

    const handle = document.createElement("span")
    handle.className = "benefits-editor__handle"
    handle.draggable = true
    handle.title = "Arraste para reordenar"
    handle.innerHTML = '<i class="bi bi-grip-vertical" aria-hidden="true"></i>'
    handle.addEventListener("dragstart", (event) => {
      this.dragged = row
      row.classList.add("is-dragging")
      event.dataTransfer.effectAllowed = "move"
      event.dataTransfer.setData("text/plain", "")
      event.dataTransfer.setDragImage(row, 16, 16)
    })
    handle.addEventListener("dragend", () => {
      row.classList.remove("is-dragging")
      this.dragged = null
      this.write()
    })

    const text = document.createElement("input")
    text.type = "text"
    text.className = "ax-control"
    text.placeholder = "Ex: Retorno rápido"
    text.value = item.text || ""
    text.setAttribute("aria-label", "Benefício")
    text.addEventListener("input", () => this.write())
    // Enter cria o próximo benefício (e não envia o formulário).
    text.addEventListener("keydown", (event) => {
      if (event.key !== "Enter") return

      event.preventDefault()
      this.add()
    })

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "ax-icon-btn benefits-editor__remove"
    remove.title = "Remover benefício"
    remove.setAttribute("aria-label", "Remover benefício")
    remove.innerHTML = '<i class="bi bi-trash" aria-hidden="true"></i>'
    remove.addEventListener("click", () => {
      row.remove()
      this.write()
    })

    row.append(handle, this.iconPicker(row), text, remove)
    return row
  }

  iconPicker(row) {
    const details = document.createElement("details")
    details.className = "benefits-editor__icon"

    const summary = document.createElement("summary")
    summary.title = "Escolher ícone"
    summary.innerHTML = `<i class="bi ${row.dataset.icon}" aria-hidden="true"></i>`

    const grid = document.createElement("div")
    grid.className = "benefits-editor__icons"
    Object.entries(this.icons()).forEach(([icon, label]) => {
      const button = document.createElement("button")
      button.type = "button"
      button.title = label
      button.setAttribute("aria-label", label)
      button.innerHTML = `<i class="bi ${icon}" aria-hidden="true"></i>`
      button.addEventListener("click", () => {
        row.dataset.icon = icon
        summary.innerHTML = `<i class="bi ${icon}" aria-hidden="true"></i>`
        details.open = false
        this.write()
      })
      grid.append(button)
    })

    // Só um seletor aberto por vez.
    details.addEventListener("toggle", () => {
      if (!details.open) return

      this.listTarget.querySelectorAll("details[open]").forEach((other) => { if (other !== details) other.open = false })
    })
    details.append(summary, grid)
    return details
  }

  icons() {
    return this.iconsValue
  }

  dragOver(event) {
    if (!this.dragged) return

    event.preventDefault()
    const before = Array.from(this.listTarget.children)
      .filter((row) => row !== this.dragged)
      .find((row) => event.clientY < row.getBoundingClientRect().top + row.offsetHeight / 2)

    if (before) this.listTarget.insertBefore(this.dragged, before)
    else this.listTarget.append(this.dragged)
  }

  drop(event) {
    event.preventDefault()
  }
}
