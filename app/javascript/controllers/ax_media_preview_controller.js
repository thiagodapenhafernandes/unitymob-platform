import { Controller } from "@hotwired/stimulus"

// Quadro de mídia (ax_media_preview): ao escolher uma imagem no campo de arquivo do corpo, mostra a nova imagem na hora;
// ao limpar a escolha, volta ao que estava (imagem salva ou "Sem imagem").
export default class extends Controller {
  disconnect() {
    this.release()
  }

  pick(event) {
    const input = event.target
    if (!(input instanceof HTMLInputElement) || input.type !== "file" || input.multiple) return

    const frame = this.element.querySelector(".ax-media-preview__frame")
    if (!frame) return

    const file = input.files?.[0]
    this.release()
    if (file?.type.startsWith("image/")) {
      this.original ??= [...frame.childNodes]
      this.url = URL.createObjectURL(file)
      const image = document.createElement("img")
      image.className = "ax-media-preview__image"
      image.alt = ""
      image.src = this.url
      frame.replaceChildren(image)
    } else if (this.original) {
      frame.replaceChildren(...this.original)
      this.original = null
    }
  }

  release() {
    if (this.url) URL.revokeObjectURL(this.url)
    this.url = null
  }
}
