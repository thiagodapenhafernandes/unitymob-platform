import { Controller } from "@hotwired/stimulus"

// Mostra/oculta colunas de uma tabela ax-* ao vivo, persistindo a escolha em
// localStorage (chave escopada por usuário). Reutilizável: a tabela marca cada
// col/th/td com data-column="<chave>" e os checkboxes com data-column-key="<chave>".
//
// Em vez de marcar cada célula, o controller escreve UM atributo data-hidden na
// tabela (lista de chaves separadas por espaço) e o CSS oculta a coluna inteira.
// Isso é robusto a re-render de linhas (turbo/lazy) porque o CSS aplica a qualquer
// célula que apareça depois.
//
//   <div data-controller="ax-table-columns"
//        data-ax-table-columns-storage-key-value="admin-habitations-columns:42">
//     <table data-ax-table-columns-target="table"> … </table>
//     <input type="checkbox" data-ax-table-columns-target="toggle"
//            data-column-key="price" data-action="change->ax-table-columns#toggle">
//   </div>
export default class extends Controller {
  static targets = ["table", "toggle"]
  static values = { storageKey: { type: String, default: "ax-table-columns" } }

  connect() {
    this.render()
    this.syncToggles()
  }

  toggle(event) {
    const key = event.target.dataset.columnKey
    if (!key) return

    // Guarda: nunca deixar a tabela sem nenhuma coluna visível.
    if (!event.target.checked && this.visibleCount() === 0) {
      event.target.checked = true
      return
    }

    const hidden = this.hiddenSet()
    if (event.target.checked) hidden.delete(key)
    else hidden.add(key)

    this.persist(hidden)
    this.render()
  }

  // Escreve o estado atual na tabela (CSS faz o resto).
  render() {
    if (!this.hasTableTarget) return
    this.tableTarget.setAttribute("data-hidden", [...this.hiddenSet()].join(" "))
  }

  syncToggles() {
    const hidden = this.hiddenSet()
    this.toggleTargets.forEach((cb) => {
      const key = cb.dataset.columnKey
      if (key) cb.checked = !hidden.has(key)
    })
  }

  visibleCount() {
    return this.toggleTargets.filter((cb) => cb.checked).length
  }

  // ----- estado -----
  hiddenSet() {
    try {
      return new Set(JSON.parse(window.localStorage.getItem(this.storageKeyValue) || "[]"))
    } catch (_) {
      return new Set()
    }
  }

  persist(set) {
    try {
      window.localStorage.setItem(this.storageKeyValue, JSON.stringify([...set]))
    } catch (_) {}
  }
}
