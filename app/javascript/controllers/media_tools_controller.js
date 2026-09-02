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
  static targets = ["modal", "shareResult", "selectionSummary"]

  static values = {
    ambienteUrl: String,
    organizeUrl: String,
    shareUrl: String,
    downloadUrl: String,
    destroySelectedUrl: String,
    canEdit: Boolean
  }

  connect() {
    this.selectedPhotoIds = new Set()
    this.selectedPictureIndices = new Set()
    this.selectedDevelopmentIndices = new Set()
    this.selectedDownloadUrls = new Map()
    this.selectedLabels = new Map()
    this.updateSelectionSummary()
  }

  disconnect() {
    this.selectedPhotoIds.clear()
    this.selectedPictureIndices.clear()
    this.selectedDevelopmentIndices.clear()
    this.selectedDownloadUrls.clear()
    this.selectedLabels.clear()
  }

  // --- Ambiente por foto -----------------------------------------------------

  async saveAmbienteInline(event) {
    event?.preventDefault?.()
    if (!this.canEditValue || !this.hasAmbienteUrlValue) return

    const select = event.currentTarget
    const photoId = event.params?.photoId
    const pictureIndex = event.params?.pictureIndex
    const hasPhotoId = photoId !== undefined && photoId !== null && photoId !== ""
    const hasPictureIndex = pictureIndex !== undefined && pictureIndex !== null && pictureIndex !== ""
    if (!select || (!hasPhotoId && !hasPictureIndex)) return

    const mediaPayload = { ambiente: select.value }
    if (hasPhotoId) {
      mediaPayload.photo_id = photoId
    } else {
      mediaPayload.picture_index = pictureIndex
    }
    this.setBusy(select, true)

    try {
      const payload = await this.requestJson(this.ambienteUrlValue, {
        method: "PATCH",
        json: { habitation: mediaPayload }
      })
      this.replaceGallery(payload)
      this.toast("Ambiente atualizado.", "success")
    } catch (error) {
      this.reportError(error)
    } finally {
      this.setBusy(select, false)
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
    const developmentIndex = event.params?.developmentIndex
    if ((photoId === undefined || photoId === null || photoId === "") &&
        (pictureIndex === undefined || pictureIndex === null || pictureIndex === "") &&
        (developmentIndex === undefined || developmentIndex === null || developmentIndex === "")) return

    const kind = this.selectionKind(photoId, pictureIndex, developmentIndex)
    const id = String(kind === "photo" ? photoId : (kind === "development" ? developmentIndex : pictureIndex))
    const selection = this.selectionSet(kind)
    const checked = event.currentTarget?.checked ?? !selection.has(id)

    if (checked) {
      selection.add(id)
      if (event.params?.downloadUrl) this.selectedDownloadUrls.set(`${kind}:${id}`, event.params.downloadUrl)
      this.selectedLabels.set(`${kind}:${id}`, event.params?.label || this.selectionFallbackLabel(kind, id))
    } else {
      selection.delete(id)
      this.selectedDownloadUrls.delete(`${kind}:${id}`)
      this.selectedLabels.delete(`${kind}:${id}`)
    }

    this.reflectSelectionState(id, checked, kind)
    this.updateSelectionSummary()
  }

  downloadSelected(event) {
    event?.preventDefault?.()

    const photoIds = Array.from(this.selectedPhotoIds)
    const pictureIndices = Array.from(this.selectedPictureIndices)
    const developmentIndices = Array.from(this.selectedDevelopmentIndices)
    if (photoIds.length === 0 && pictureIndices.length === 0 && developmentIndices.length === 0) {
      this.toast("Selecione ao menos uma foto para baixar.", "warning")
      return
    }

    if (this.hasDownloadUrlValue) {
      this.submitDownloadForm(photoIds, pictureIndices, developmentIndices)
      return
    }

    this.downloadUrlsDirectly()
  }

  selectAll(event) {
    event?.preventDefault?.()

    this.selectionInputs().forEach((input) => {
      if (input.disabled || input.checked) return

      input.click()
    })
  }

  async runBulkAction(event) {
    const select = event?.currentTarget
    const action = select?.value || ""
    if (!action) return

    select.value = ""

    if (action === "download") {
      this.downloadSelected(event)
      return
    }

    if (action === "delete") {
      await this.destroySelected(event)
    }
  }

  async destroySelected(event) {
    event?.preventDefault?.()
    if (!this.canEditValue || !this.hasDestroySelectedUrlValue) return

    const photoIds = Array.from(this.selectedPhotoIds)
    const pictureIndices = Array.from(this.selectedPictureIndices)
    const developmentCount = this.selectedDevelopmentIndices.size
    const totalDeletable = photoIds.length + pictureIndices.length

    if (totalDeletable === 0) {
      const suffix = developmentCount > 0 ? " Fotos do empreendimento só podem ser baixadas." : ""
      this.toast(`Selecione ao menos uma foto do imóvel para excluir.${suffix}`, "warning")
      return
    }

    const message = `Excluir ${totalDeletable} foto${totalDeletable === 1 ? "" : "s"} selecionada${totalDeletable === 1 ? "" : "s"}? Essa ação não pode ser desfeita.`
    if (!window.confirm(message)) return

    this.setBusy(event?.currentTarget, true)

    try {
      const payload = await this.requestJson(this.destroySelectedUrlValue, {
        method: "DELETE",
        json: { habitation: { photo_ids: photoIds, picture_indices: pictureIndices } }
      })
      this.selectedPhotoIds.clear()
      this.selectedPictureIndices.clear()
      this.selectedDownloadUrls.clear()
      this.selectedLabels.clear()
      this.replaceGallery(payload)
      this.toast(payload.message || "Fotos excluídas.", "success")
    } catch (error) {
      this.reportError(error)
    } finally {
      this.setBusy(event?.currentTarget, false)
    }
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
    this.updateSelectionSummary()
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
    const attribute = kind === "picture" ? "data-media-tools-picture-index-param" : (kind === "development" ? "data-media-tools-development-index-param" : "data-media-tools-photo-id-param")
    const input = this.element.querySelector(`[data-action*="media-tools#toggleSelect"][${attribute}="${CSS.escape(id)}"]`)
    input?.closest(".ax-media-grid__item")?.classList?.toggle("is-media-selected", checked)
  }

  prunAndReflectSelection() {
    const container = this.previewContainer(this.photoUploadController())
    const presentPhotos = new Set()
    const presentPictures = new Set()
    const presentDevelopments = new Set()

    container?.querySelectorAll('[data-action*="media-tools#toggleSelect"]').forEach((input) => {
      const photoId = input.getAttribute("data-media-tools-photo-id-param")
      const pictureIndex = input.getAttribute("data-media-tools-picture-index-param")
      const developmentIndex = input.getAttribute("data-media-tools-development-index-param")
      if (photoId !== null) presentPhotos.add(String(photoId))
      if (pictureIndex !== null) presentPictures.add(String(pictureIndex))
      if (developmentIndex !== null) presentDevelopments.add(String(developmentIndex))
    })

    if (presentPhotos.size > 0) {
      Array.from(this.selectedPhotoIds).forEach((id) => {
        if (!presentPhotos.has(id)) {
          this.selectedPhotoIds.delete(id)
          this.selectedLabels.delete(`photo:${id}`)
        }
      })
    }
    if (presentPictures.size > 0) {
      Array.from(this.selectedPictureIndices).forEach((id) => {
        if (!presentPictures.has(id)) {
          this.selectedPictureIndices.delete(id)
          this.selectedLabels.delete(`picture:${id}`)
        }
      })
    }
    if (presentDevelopments.size > 0) {
      Array.from(this.selectedDevelopmentIndices).forEach((id) => {
        if (!presentDevelopments.has(id)) {
          this.selectedDevelopmentIndices.delete(id)
          this.selectedLabels.delete(`development:${id}`)
        }
      })
    }

    this.selectedDownloadUrls.clear()
    container?.querySelectorAll('[data-action*="media-tools#toggleSelect"]').forEach((input) => {
      const photoId = input.getAttribute("data-media-tools-photo-id-param")
      const pictureIndex = input.getAttribute("data-media-tools-picture-index-param")
      const developmentIndex = input.getAttribute("data-media-tools-development-index-param")
      const kind = photoId !== null ? "photo" : (developmentIndex !== null ? "development" : "picture")
      const id = String(kind === "photo" ? photoId : (kind === "development" ? developmentIndex : pictureIndex))
      const checked = this.selectionSet(kind).has(id)
      if ("checked" in input) input.checked = checked
      input.closest(".ax-media-grid__item")?.classList?.toggle("is-media-selected", checked)
      if (checked && input.getAttribute("data-media-tools-download-url-param")) {
        this.selectedDownloadUrls.set(`${kind}:${id}`, input.getAttribute("data-media-tools-download-url-param"))
      }
      if (checked) {
        this.selectedLabels.set(`${kind}:${id}`, input.getAttribute("data-media-tools-label-param") || this.selectionFallbackLabel(kind, id))
      }
    })
  }

  updateSelectionSummary() {
    if (!this.hasSelectionSummaryTarget) return

    const labels = [
      ...Array.from(this.selectedPhotoIds).map((id) => this.selectedLabels.get(`photo:${id}`) || this.selectionFallbackLabel("photo", id)),
      ...Array.from(this.selectedPictureIndices).map((id) => this.selectedLabels.get(`picture:${id}`) || this.selectionFallbackLabel("picture", id)),
      ...Array.from(this.selectedDevelopmentIndices).map((id) => this.selectedLabels.get(`development:${id}`) || this.selectionFallbackLabel("development", id))
    ].filter(Boolean)

    if (labels.length === 0) {
      this.selectionSummaryTarget.hidden = true
      this.selectionSummaryTarget.textContent = ""
      this.selectionSummaryTarget.removeAttribute("title")
      this.selectionSummaryTarget.removeAttribute("aria-label")
      return
    }

    const first = labels[0]
    this.selectionSummaryTarget.hidden = false
    this.selectionSummaryTarget.textContent = labels.length === 1 ? first : `${first} +${labels.length - 1}`
    this.selectionSummaryTarget.title = labels.join("\n")
    this.selectionSummaryTarget.setAttribute("aria-label", `${labels.length} foto${labels.length === 1 ? "" : "s"} selecionada${labels.length === 1 ? "" : "s"}: ${labels.join(", ")}`)
  }

  // --- Modal -----------------------------------------------------------------

  showModal() {
    if (!this.hasModalTarget) return
    this.modalTarget.hidden = false
    this.modalTarget.classList.add("is-open")
    this.modalTarget.setAttribute("aria-hidden", "false")
  }

  hideModal(event) {
    event?.preventDefault?.()
    if (!this.hasModalTarget) return
    this.modalTarget.hidden = true
    this.modalTarget.classList.remove("is-open")
    this.modalTarget.setAttribute("aria-hidden", "true")
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

  submitDownloadForm(photoIds, pictureIndices, developmentIndices = []) {
    const form = document.createElement("form")
    form.method = "post"
    form.action = this.downloadUrlValue
    form.target = "_blank"
    form.dataset.turbo = "false"

    const csrfToken = this.csrfToken()
    if (csrfToken) this.appendHiddenField(form, "authenticity_token", csrfToken)
    photoIds.forEach((id) => this.appendHiddenField(form, "habitation[photo_ids][]", id))
    pictureIndices.forEach((index) => this.appendHiddenField(form, "habitation[picture_indices][]", index))
    developmentIndices.forEach((index) => this.appendHiddenField(form, "habitation[development_indices][]", index))

    document.body.appendChild(form)
    form.submit()
    form.remove()
  }

  selectionKind(photoId, pictureIndex, developmentIndex) {
    if (photoId !== undefined && photoId !== null && photoId !== "") return "photo"
    if (developmentIndex !== undefined && developmentIndex !== null && developmentIndex !== "") return "development"
    return "picture"
  }

  selectionSet(kind) {
    if (kind === "photo") return this.selectedPhotoIds
    if (kind === "development") return this.selectedDevelopmentIndices
    return this.selectedPictureIndices
  }

  selectionInputs() {
    return Array.from(this.element.querySelectorAll('[data-action*="media-tools#toggleSelect"]'))
  }

  selectionFallbackLabel(kind, id) {
    if (kind === "development") return `Foto do empreendimento ${Number(id) + 1}`
    if (kind === "picture") return `Foto externa ${Number(id) + 1}`
    return `Foto ${id}`
  }

  appendHiddenField(form, name, value) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    form.appendChild(input)
  }

  downloadUrlsDirectly() {
    const urls = Array.from(this.selectedDownloadUrls.values()).filter(Boolean)
    if (urls.length === 0) {
      this.toast("Selecione ao menos uma foto para baixar.", "warning")
      return
    }

    urls.forEach((url, index) => {
      window.setTimeout(() => {
        const link = document.createElement("a")
        link.href = url
        link.download = ""
        link.rel = "noopener"
        document.body.appendChild(link)
        link.click()
        link.remove()
      }, index * 150)
    })
  }

  setBusy(button, isBusy) {
    if (!button) return
    button.disabled = isBusy
    button.classList.toggle("is-loading", isBusy)
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
