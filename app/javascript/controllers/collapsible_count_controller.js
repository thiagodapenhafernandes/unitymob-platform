import { Controller } from "@hotwired/stimulus"

// Atualiza o resumo (ex: "1234 formulários selecionados") de um <select multiple>
// colocado dentro de um <details>.
//
// HTML esperado:
//   <div data-controller="collapsible-count">
//     <details data-collapsible-count-target="details">
//       <summary>
//         ... <span data-collapsible-count-target="label">N selecionados</span> ...
//       </summary>
//       <select multiple data-action="change->collapsible-count#recount">
//     </details>
//   </div>
export default class extends Controller {
  static targets = ["label", "details"]

  recount(event) {
    const select = event?.target?.tagName === "SELECT"
      ? event.target
      : this.element.querySelector("select[multiple]")
    if (!select || !this.hasLabelTarget) return

    const count = Array.from(select.selectedOptions).filter((o) => o.value).length
    this.labelTarget.innerHTML = this.format(count)
  }

  format(count) {
    if (count === 0) return "Nenhum formulário selecionado"
    if (count === 1) return "<strong>1</strong> formulário selecionado"
    return `<strong>${count.toLocaleString("pt-BR")}</strong> formulários selecionados`
  }
}
