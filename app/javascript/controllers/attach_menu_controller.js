import AxPopoverController from "controllers/ax_popover_controller"

// Menu "+" do composer (estilo WhatsApp): Documento / Fotos e vídeos / Câmera /
// Áudio. Todos reusam o MESMO input de arquivo do wa-composer — só ajustamos
// accept/capture antes de abrir o seletor. Validação/pipeline continuam iguais.
export default class extends AxPopoverController {
  pick(event) {
    const item = event.currentTarget
    const input = this.fileInput
    if (!input) return

    input.setAttribute("accept", item.dataset.accept || "")
    if (item.dataset.capture) {
      input.setAttribute("capture", item.dataset.capture)
    } else {
      input.removeAttribute("capture")
    }
    this.close()
    input.click()
  }

  get fileInput() {
    return this.element.closest("form")?.querySelector('[data-wa-composer-target="fileInput"]')
  }
}
