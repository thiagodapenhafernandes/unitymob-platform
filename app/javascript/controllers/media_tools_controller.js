import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="media-tools"
//
// Ferramentas de organização de fotos do imóvel (ambiente por foto, organizar
// por ambiente e envio/compartilhamento de fotos selecionadas). Convive no MESMO
// elemento raiz do manager que o controller "photo-upload": este controller NÃO
// implementa arraste — ele apenas troca o innerHTML da galeria pelo gallery_html
// retornado pelo backend e delega ao photo-upload a reinicialização do arraste
// (refreshMediaDragAndDrop), preservando o previewContainer alvo intacto.
export default class extends Controller {
  static targets = ["modal", "ambienteSelect", "ambientePositionInput", "ambienteSaveButton", "shareResult"]

  static values = {
    ambienteUrl: String,
    organizeUrl: String,
    shareUrl: String,
    ambientes: Array,
    canEdit: Boolean
  }

  connect() {
    this.activePhotoId = null
    this.activePictureIndex = null
    this.selectedPhotoIds = new Set()
    this.selectedPictureIndices = new Set()
    this.populateAmbienteOptions()
  }

  disconnect() {
    this.selectedPhotoIds.clear()
    this.selectedPictureIndices.clear()
  }

  // --- Ambiente por foto -----------------------------------------------------

  openSettings(event) {
    if (!this.canEditValue) return

    const photoId = event.params?.photoId
    const pictureIndex = event.params?.pictureIndex
    const hasPhotoId = photoId !== undefined && photoId !== null && photoId !== ""
    const hasPictureIndex = pictureIndex !== undefined && pictureIndex !== null && pictureIndex !== ""
    if (!hasPhotoId && !hasPictureIndex) return

    this.activePhotoId = hasPhotoId ? String(photoId) : null
    this.activePictureIndex = hasPictureIndex ? String(pictureIndex) : null
    const current = event.params?.ambiente ?? ""
    const currentPosition = event.params?.ambientePosition ?? ""

    if (this.hasAmbienteSelectTarget) {
      this.ambienteSelectTarget.value = current
    }
    if (this.hasAmbientePositionInputTarget) {
      this.ambientePositionInputTarget.value = currentPosition
    }

    // Modo ambiente: esconde um resultado de compartilhamento que tenha ficado.
    if (this.hasShareResultTarget) {
      this.shareResultTarget.hidden = true
      this.shareResultTarget.innerHTML = ""
    }

    this.resetAmbienteSaveButton()
    this.showModal()
  }

  closeSettings(event) {
    event?.preventDefault?.()
    this.resetAmbienteSaveButton()
    this.hideModal()
    this.activePhotoId = null
    this.activePictureIndex = null
  }

  async saveAmbiente(event) {
    event?.preventDefault?.()
    if (!this.canEditValue || !this.hasAmbienteUrlValue || (this.activePhotoId === null && this.activePictureIndex === null)) return

    const ambiente = this.hasAmbienteSelectTarget ? this.ambienteSelectTarget.value : ""
    const ambientePosition = this.hasAmbientePositionInputTarget ? this.ambientePositionInputTarget.value : ""
    const mediaPayload = { ambiente, ambiente_position: ambientePosition }
    if (this.activePhotoId !== null) {
      mediaPayload.photo_id = this.activePhotoId
    } else {
      mediaPayload.picture_index = this.activePictureIndex
    }
    this.setBusy(event?.currentTarget, true)

    try {
      const payload = await this.requestJson(this.ambienteUrlValue, {
        method: "PATCH",
        json: { habitation: mediaPayload }
      })
      this.replaceGallery(payload)
      this.resetAmbienteSaveButton()
      this.hideModal()
      this.activePhotoId = null
      this.activePictureIndex = null
    } catch (error) {
      this.reportError(error)
    } finally {
      this.setBusy(event?.currentTarget, false)
    }
  }

  // --- Organizar por ambiente ------------------------------------------------

  async organize(event) {
    event?.preventDefault?.()
    if (!this.canEditValue || !this.hasOrganizeUrlValue) return

    this.setBusy(event?.currentTarget, true)

    try {
      const payload = await this.requestJson(this.organizeUrlValue, { method: "POST" })
      this.replaceGallery(payload)
    } catch (error) {
      this.reportError(error)
    } finally {
      this.setBusy(event?.currentTarget, false)
    }
  }

  // --- Seleção e compartilhamento --------------------------------------------

  toggleSelect(event) {
    const photoId = event.params?.photoId
    const pictureIndex = event.params?.pictureIndex
    if ((photoId === undefined || photoId === null || photoId === "") &&
        (pictureIndex === undefined || pictureIndex === null || pictureIndex === "")) return

    const id = String(photoId ?? pictureIndex)
    const selection = photoId === undefined || photoId === null || photoId === "" ? this.selectedPictureIndices : this.selectedPhotoIds
    const checked = event.currentTarget?.checked ?? !selection.has(id)

    if (checked) {
      selection.add(id)
    } else {
      selection.delete(id)
    }

    this.reflectSelectionState(id, checked, photoId === undefined || photoId === null || photoId === "" ? "picture" : "photo")
  }

  async openShare(event) {
    event?.preventDefault?.()
    if (!this.hasShareUrlValue) return

    // O resultado (link + WhatsApp) vive dentro do modal — sem abri-lo o usuário
    // clicaria em "Enviar" e não veria nada.
    this.showModal()

    const photoIds = Array.from(this.selectedPhotoIds)
    const pictureIndices = Array.from(this.selectedPictureIndices)
    if (photoIds.length === 0 && pictureIndices.length === 0) {
      this.renderShareResult({ error: "Selecione ao menos uma foto para enviar." })
      return
    }

    this.setBusy(event?.currentTarget, true)

    try {
      const payload = await this.requestJson(this.shareUrlValue, {
        method: "POST",
        json: { habitation: { photo_ids: photoIds, picture_indices: pictureIndices } }
      })
      this.renderShareResult(payload)
    } catch (error) {
      this.renderShareResult({ error: this.errorMessage(error) })
    } finally {
      this.setBusy(event?.currentTarget, false)
    }
  }

  // --- Galeria / re-render seguro --------------------------------------------

  // Troca o innerHTML da galeria pelo gallery_html retornado e delega ao
  // controller photo-upload a reinicialização do arraste. NÃO reimplementamos o
  // arraste aqui: encontramos a instância de photo-upload no MESMO elemento e
  // chamamos os mesmos métodos que ele usa após um re-render (applyMediaPayload
  // quando disponível — que já troca o previewContainer.innerHTML e chama
  // refreshMediaDragAndDrop — ou, em fallback, replaceGallery + refresh direto).
  replaceGallery(payload) {
    if (!payload || typeof payload.gallery_html !== "string") return

    const uploader = this.photoUploadController()

    if (uploader && typeof uploader.applyMediaPayload === "function") {
      uploader.applyMediaPayload(payload)
    } else {
      const container = this.previewContainer(uploader)
      if (container) container.innerHTML = payload.gallery_html
      uploader?.refreshMediaDragAndDrop?.()
      uploader?.updateOrder?.()
      uploader?.refreshPhotoBadges?.()
    }

    // A galeria foi recriada: limpa seleção órfã e reaplica estado visual dos
    // checkboxes que sobreviveram (mesmos photo_ids).
    this.prunAndReflectSelection()
  }

  photoUploadController() {
    if (!this.application?.getControllerForElementAndIdentifier) return null
    return this.application.getControllerForElementAndIdentifier(this.element, "photo-upload")
  }

  previewContainer(uploader) {
    if (uploader?.hasPreviewContainerTarget) return uploader.previewContainerTarget
    return this.element.querySelector('[data-photo-upload-target="previewContainer"]')
  }

  // --- Estado da seleção -----------------------------------------------------

  reflectSelectionState(id, checked, kind = "photo") {
    const attribute = kind === "picture" ? "data-media-tools-picture-index-param" : "data-media-tools-photo-id-param"
    const input = this.element.querySelector(`[data-action*="media-tools#toggleSelect"][${attribute}="${CSS.escape(id)}"]`)
    input?.closest(".ax-media-grid__item")?.classList?.toggle("is-media-selected", checked)
  }

  prunAndReflectSelection() {
    const container = this.previewContainer(this.photoUploadController())
    const presentPhotos = new Set()
    const presentPictures = new Set()

    container?.querySelectorAll('[data-action*="media-tools#toggleSelect"]').forEach((input) => {
      const photoId = input.getAttribute("data-media-tools-photo-id-param")
      const pictureIndex = input.getAttribute("data-media-tools-picture-index-param")
      if (photoId !== null) presentPhotos.add(String(photoId))
      if (pictureIndex !== null) presentPictures.add(String(pictureIndex))
    })

    if (presentPhotos.size > 0) {
      Array.from(this.selectedPhotoIds).forEach((id) => {
        if (!presentPhotos.has(id)) this.selectedPhotoIds.delete(id)
      })
    }
    if (presentPictures.size > 0) {
      Array.from(this.selectedPictureIndices).forEach((id) => {
        if (!presentPictures.has(id)) this.selectedPictureIndices.delete(id)
      })
    }

    container?.querySelectorAll('[data-action*="media-tools#toggleSelect"]').forEach((input) => {
      const photoId = input.getAttribute("data-media-tools-photo-id-param")
      const pictureIndex = input.getAttribute("data-media-tools-picture-index-param")
      const checked = photoId !== null ? this.selectedPhotoIds.has(String(photoId)) : this.selectedPictureIndices.has(String(pictureIndex))
      if ("checked" in input) input.checked = checked
      input.closest(".ax-media-grid__item")?.classList?.toggle("is-media-selected", checked)
    })
  }

  // --- Modal -----------------------------------------------------------------

  showModal() {
    if (!this.hasModalTarget) return
    this.modalTarget.hidden = false
    this.modalTarget.classList.add("is-open")
    this.modalTarget.setAttribute("aria-hidden", "false")
  }

  hideModal() {
    if (!this.hasModalTarget) return
    this.modalTarget.hidden = true
    this.modalTarget.classList.remove("is-open")
    this.modalTarget.setAttribute("aria-hidden", "true")
  }

  populateAmbienteOptions() {
    if (!this.hasAmbienteSelectTarget) return
    // A view normalmente já emite as <option>. Só preenchemos se o select vier
    // vazio (defensivo), preservando a opção "sem ambiente" (valor vazio).
    if (this.ambienteSelectTarget.options.length > 1) return

    const ambientes = Array.isArray(this.ambientesValue) ? this.ambientesValue : []
    if (ambientes.length === 0) return

    const fragment = document.createDocumentFragment()
    const blank = document.createElement("option")
    blank.value = ""
    blank.textContent = "Não informado"
    fragment.appendChild(blank)

    ambientes.forEach((ambiente) => {
      const option = document.createElement("option")
      option.value = ambiente
      option.textContent = ambiente
      fragment.appendChild(option)
    })

    this.ambienteSelectTarget.innerHTML = ""
    this.ambienteSelectTarget.appendChild(fragment)
  }

  // --- Resultado do share ----------------------------------------------------

  renderShareResult(payload) {
    if (!this.hasShareResultTarget) return

    if (payload?.error) {
      this.shareResultTarget.hidden = false
      this.shareResultTarget.classList.add("is-error")
      this.shareResultTarget.innerHTML = `
        <p class="ax-media-share__message ax-media-share__message--error">${this.escapeHtml(payload.error)}</p>
      `
      return
    }

    const shareUrl = payload?.share_url || ""
    const whatsappUrl = payload?.whatsapp_url || ""
    this.shareResultTarget.hidden = false
    this.shareResultTarget.classList.remove("is-error")
    this.shareResultTarget.innerHTML = `
      <div class="ax-media-share__result">
        <label class="ax-media-share__label">Link da galeria</label>
        <div class="ax-media-share__link-row">
          <input type="text" class="ax-media-share__link" value="${this.escapeAttr(shareUrl)}" readonly>
          <button type="button" class="ax-media-action ax-media-action--pill ax-media-share__copy" data-action="media-tools#copyShareLink" title="Copiar link" aria-label="Copiar link">
            <i class="bi bi-clipboard"></i>
          </button>
        </div>
        ${whatsappUrl ? `
        <a class="ax-btn ax-btn--primary ax-media-share__whatsapp" href="${this.escapeAttr(whatsappUrl)}" target="_blank" rel="noopener">
          <i class="bi bi-whatsapp"></i>
          Enviar por WhatsApp
        </a>` : ""}
      </div>
    `
  }

  async copyShareLink(event) {
    event?.preventDefault?.()
    const input = this.shareResultTarget?.querySelector(".ax-media-share__link")
    if (!input) return

    const value = input.value
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(value)
      } else {
        input.select()
        document.execCommand("copy")
      }
      this.toast("Link copiado", "success")
      const button = event.currentTarget
      const icon = button?.querySelector("i")
      if (icon) {
        icon.classList.remove("bi-clipboard")
        icon.classList.add("bi-clipboard-check")
        window.setTimeout(() => {
          icon.classList.remove("bi-clipboard-check")
          icon.classList.add("bi-clipboard")
        }, 1800)
      }
    } catch (_error) {
      input.select()
      this.toast("Copie manualmente", "warning")
    }
  }

  toast(message, type = "info") {
    if (window.axToast) window.axToast({ message, type, timeout: 2400 })
  }

  // --- Infra HTTP (padrão do projeto: fetch + X-CSRF-Token) ------------------

  async requestJson(url, options = {}) {
    const headers = {
      "Accept": "application/json",
      "X-Requested-With": "XMLHttpRequest"
    }
    const csrfToken = this.csrfToken()
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken

    const requestOptions = { method: options.method || "GET", headers }

    if (options.json) {
      requestOptions.body = JSON.stringify(options.json)
      requestOptions.headers["Content-Type"] = "application/json"
    }

    const response = await fetch(url, requestOptions)
    const contentType = response.headers.get("content-type") || ""
    const payload = contentType.includes("application/json") ? await response.json() : {}

    if (response.status === 403) {
      throw new Error(payload.error || "Você não tem permissão para organizar as fotos deste imóvel.")
    }

    if (!response.ok || payload.ok === false) {
      const message = payload.error || (Array.isArray(payload.errors) ? payload.errors.join(", ") : null)
      throw new Error(message || "A operação de mídia não pôde ser concluída.")
    }

    return payload
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  setBusy(button, isBusy) {
    if (!button) return
    button.disabled = isBusy
    button.classList.toggle("is-loading", isBusy)
  }

  resetAmbienteSaveButton() {
    if (!this.hasAmbienteSaveButtonTarget) return

    this.setBusy(this.ambienteSaveButtonTarget, false)
  }

  reportError(error) {
    const message = this.errorMessage(error)
    if (this.hasShareResultTarget) {
      this.renderShareResult({ error: message })
      return
    }
    window.alert(message)
  }

  errorMessage(error) {
    return error?.message || "Não foi possível concluir a operação agora."
  }

  escapeHtml(value) {
    const span = document.createElement("span")
    span.textContent = value || ""
    return span.innerHTML
  }

  escapeAttr(value) {
    return String(value || "").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
}
