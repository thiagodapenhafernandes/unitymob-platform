import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "fileInput",
    "frame",
    "logo",
    "opacityInput",
    "opacityValue",
    "placeholder",
    "placeholderTitle",
    "placeholderMessage",
    "removeInput",
    "positionInput",
    "sizeInput",
    "sizeValue"
  ]

  connect() {
    this.savedSource = this.hasLogoTarget ? this.logoTarget.getAttribute("src") : null
    this.imageFailedState = Boolean(this.savedSource && this.logoTarget.complete && !this.logoTarget.naturalWidth)
    this.resizeObserver = new ResizeObserver(() => this.updateMargin())
    if (this.hasFrameTarget) this.resizeObserver.observe(this.frameTarget)
    this.update()
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    this.revokePreviewUrl()
  }

  update() {
    this.updateMargin()
    this.updatePosition()
    this.updateSize()
    this.updateOpacity()
    this.updatePreview()
  }

  loadFile() {
    if (!this.hasFileInputTarget || !this.hasLogoTarget) return

    const file = this.fileInputTarget.files[0]
    this.revokePreviewUrl()
    this.imageFailedState = false

    if (file) {
      this.previewUrl = URL.createObjectURL(file)
      this.logoTarget.src = this.previewUrl
      if (this.hasRemoveInputTarget) this.removeInputTarget.checked = false
    } else if (this.savedSource) {
      this.logoTarget.src = this.savedSource
    } else {
      this.logoTarget.removeAttribute("src")
    }

    this.update()
  }

  imageLoaded() {
    this.imageFailedState = false
    this.updatePreview()
  }

  imageFailed() {
    this.imageFailedState = true
    this.updatePreview()
  }

  updatePreview() {
    if (!this.hasLogoTarget) return

    const removing = this.hasRemoveInputTarget && this.removeInputTarget.checked
    const source = this.logoTarget.getAttribute("src")
    const visible = Boolean(!removing && source && !this.imageFailedState && this.logoTarget.complete && this.logoTarget.naturalWidth)
    this.logoTarget.hidden = !visible
    this.logoTarget.classList.toggle("tw-hidden", !visible)

    if (!this.hasPlaceholderTarget) return
    this.placeholderTarget.hidden = visible
    this.placeholderTarget.classList.toggle("tw-hidden", visible)

    let title = "Envie uma imagem"
    let message = "A prévia aparecerá aqui antes de salvar."
    if (removing) {
      title = "Marca será removida ao salvar"
      message = "Desmarque a remoção para manter a imagem atual."
    } else if (source && this.imageFailedState) {
      title = "Não foi possível carregar a imagem"
      message = "Selecione outra imagem para conferir a prévia."
    } else if (source && !visible) {
      title = "Carregando prévia"
      message = "Aguarde o carregamento da imagem."
    }
    if (this.hasPlaceholderTitleTarget) this.placeholderTitleTarget.textContent = title
    if (this.hasPlaceholderMessageTarget) this.placeholderMessageTarget.textContent = message
  }

  updateMargin() {
    if (this.hasFrameTarget) this.frameTarget.style.setProperty("--watermark-margin", `${this.frameTarget.clientWidth * 0.035}px`)
  }

  updatePosition() {
    if (!this.hasLogoTarget) return

    const selected = this.positionInputTargets.find((input) => input.checked)
    if (!selected) return

    this.logoTarget.classList.remove(
      "watermark-position-top_left",
      "watermark-position-top_right",
      "watermark-position-bottom_left",
      "watermark-position-bottom_right",
      "watermark-position-center"
    )
    this.logoTarget.classList.add(`watermark-position-${selected.value}`)
  }

  updateSize() {
    if (!this.hasSizeInputTarget || !this.hasFrameTarget) return

    const size = this.sizeInputTarget.value
    this.frameTarget.style.setProperty("--watermark-size", `${size}%`)

    if (this.hasLogoTarget) {
      this.logoTarget.style.width = `${size}%`
    }

    if (this.hasSizeValueTarget) {
      this.sizeValueTarget.textContent = `${size}%`
    }
  }

  updateOpacity() {
    if (!this.hasOpacityInputTarget || !this.hasFrameTarget) return

    const opacity = this.opacityInputTarget.value
    this.frameTarget.style.setProperty("--watermark-opacity", opacity / 100)

    if (this.hasLogoTarget) {
      this.logoTarget.style.opacity = opacity / 100
    }

    if (this.hasOpacityValueTarget) {
      this.opacityValueTarget.textContent = `${opacity}%`
    }
  }

  revokePreviewUrl() {
    if (!this.previewUrl) return

    URL.revokeObjectURL(this.previewUrl)
    this.previewUrl = null
  }
}
