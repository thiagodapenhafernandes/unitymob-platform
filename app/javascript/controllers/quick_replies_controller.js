import AxPopoverController from "controllers/ax_popover_controller"

// "⚡ Respostas rápidas" do composer: cartões de apresentação (preenchem o
// campo, editáveis) e modelos aprovados da Meta (definem o modo template).
// Reusa a fiação existente: evento wa-presentation:fill e o select escondido
// do wa-composer — nenhum fluxo novo de envio.
export default class extends AxPopoverController {
  useCard(event) {
    const item = event.currentTarget
    window.dispatchEvent(new CustomEvent("wa-presentation:fill", {
      detail: { cardId: item.dataset.cardId, body: item.dataset.body || "" }
    }))
    this.close()
  }

  openCards() {
    this.close()
    document.querySelector("[data-pc-manager-trigger]")?.click()
  }

  useTemplate(event) {
    const select = this.element.closest("form")?.querySelector('[data-wa-composer-target="template"]')
    if (!select) return

    select.value = event.currentTarget.dataset.templateName || ""
    select.dispatchEvent(new Event("change", { bubbles: true }))
    this.close()
  }
}
