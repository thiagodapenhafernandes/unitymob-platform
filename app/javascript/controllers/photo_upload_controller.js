import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Connects to data-controller="photo-upload"
export default class extends Controller {
  static targets = [
    "input",
    "orderInput",
    "apiOrderInput",
    "hiddenPhotoIdsInput",
    "hiddenPictureUrlsInput",
    "removePhotoIdsInput",
    "removePictureIndicesInput",
    "uploadLimitFeedback",
    "previewContainer"
  ]

  static values = {
    async: Boolean,
    uploadUrl: String,
    reorderUrl: String,
    visibilityUrl: String,
    destroyUrl: String
  }

  static maxUploadBytes = 250 * 1024 * 1024

  connect() {
    this.selectedNewFiles = []
    this.newFileIdCounter = 0
    this.boundHandleDragOver = this.handleDragOver.bind(this)
    this.boundHandleDrop = this.handleDrop.bind(this)
    this.boundHandleDragLeave = this.handleDragLeave.bind(this)
    this.boundHandleFormSubmit = this.handleFormSubmit.bind(this)
    this.boundHandleSortableAutoScrollPointer = this.handleSortableAutoScrollPointer.bind(this)
    this.form = this.element.closest('form')

    this.initSortable()

    // Drag and Drop
    this.element.addEventListener('dragover', this.boundHandleDragOver)
    this.element.addEventListener('drop', this.boundHandleDrop)
    this.element.addEventListener('dragleave', this.boundHandleDragLeave)
    if (this.form) this.form.addEventListener('submit', this.boundHandleFormSubmit, true)
  }

  disconnect() {
    if (this.sortable) this.sortable.destroy()
    this.stopSortableAutoScroll()
    this.element.removeEventListener('dragover', this.boundHandleDragOver)
    this.element.removeEventListener('drop', this.boundHandleDrop)
    this.element.removeEventListener('dragleave', this.boundHandleDragLeave)
    if (this.form) this.form.removeEventListener('submit', this.boundHandleFormSubmit, true)
  }

  handleDragOver(e) {
    e.preventDefault()
    e.stopPropagation()
    this.element.classList.add('is-dragging-files')
  }

  handleDragLeave(e) {
    e.preventDefault()
    if (this.element.contains(e.relatedTarget)) return

    this.element.classList.remove('is-dragging-files')
  }

  handleDrop(e) {
    e.preventDefault()
    e.stopPropagation()
    this.element.classList.remove('is-dragging-files')

    if (e.dataTransfer && e.dataTransfer.files.length > 0) {
      if (this.hasInputTarget) {
        this.inputTarget.files = e.dataTransfer.files
        this.inputTarget.dispatchEvent(new Event('change', { bubbles: true }))
      }
    }
  }

  initSortable() {
    // Only initialize if container exists
    if (!this.hasPreviewContainerTarget) return

    this.sortable = new Sortable(this.previewContainerTarget, {
      animation: 150,
      ghostClass: 'sortable-ghost',
      chosenClass: 'sortable-chosen',
      dragClass: 'sortable-drag',
      handle: '.media-photo-drag-handle',
      draggable: '.draggable-item',
      direction: this.resolveSortableDirection.bind(this),
      forceFallback: true,
      fallbackOnBody: true,
      fallbackTolerance: 3,
      fallbackClass: 'ax-media-sortable-fallback',
      scroll: true,
      bubbleScroll: true,
      scrollSensitivity: 148,
      scrollSpeed: 28,
      swapThreshold: 0.72,
      invertSwap: true,
      invertedSwapThreshold: 0.28,
      emptyInsertThreshold: 88,
      onClone: (evt) => {
        this.prepareSortableFallback(evt)
      },
      onStart: (evt) => {
        this.startSortableAutoScroll(evt?.originalEvent)
      },
      onMove: (evt) => {
        this.handleSortableAutoScrollPointer(evt?.originalEvent)
        return true
      },
      onEnd: (evt) => {
        this.stopSortableAutoScroll()
        this.syncNewFilesFromDom()
        this.updateOrder()
        this.refreshPhotoBadges()
        this.syncReorder()
      },
      onUnchoose: () => {
        this.stopSortableAutoScroll()
      }
    })
  }

  prepareSortableFallback(event) {
    const item = event?.item
    const clone = event?.clone
    if (!item || !clone) return

    const rect = item.getBoundingClientRect()
    if (!rect.width || !rect.height) return

    clone.style.width = `${Math.round(rect.width)}px`
    clone.style.maxWidth = `${Math.round(rect.width)}px`
    clone.style.height = `${Math.round(rect.height)}px`
    clone.style.boxSizing = "border-box"
  }

  resolveSortableDirection(_event, target, dragEl) {
    if (!target || !dragEl) return "horizontal"

    const targetRect = target.getBoundingClientRect()
    const dragRect = dragEl.getBoundingClientRect()
    const targetCenterY = targetRect.top + targetRect.height / 2
    const dragCenterY = dragRect.top + dragRect.height / 2
    const sameRowTolerance = Math.min(targetRect.height, dragRect.height) * 0.7

    return Math.abs(targetCenterY - dragCenterY) <= sameRowTolerance ? "horizontal" : "vertical"
  }

  startSortableAutoScroll(event) {
    this.sortableScrollContainer = this.resolveSortableScrollContainer()
    this.sortableAutoScrollActive = true
    this.previewContainerTarget.classList.add("is-sorting")
    this.sortableScrollContainer?.classList?.add("is-sorting")
    this.handleSortableAutoScrollPointer(event)

    window.addEventListener("pointermove", this.boundHandleSortableAutoScrollPointer, { passive: true })
    window.addEventListener("mousemove", this.boundHandleSortableAutoScrollPointer, { passive: true })
    window.addEventListener("touchmove", this.boundHandleSortableAutoScrollPointer, { passive: true })

    if (!this.sortableAutoScrollFrame) {
      this.sortableAutoScrollFrame = window.requestAnimationFrame(() => this.runSortableAutoScroll())
    }
  }

  stopSortableAutoScroll() {
    window.removeEventListener("pointermove", this.boundHandleSortableAutoScrollPointer)
    window.removeEventListener("mousemove", this.boundHandleSortableAutoScrollPointer)
    window.removeEventListener("touchmove", this.boundHandleSortableAutoScrollPointer)

    if (this.sortableAutoScrollFrame) {
      window.cancelAnimationFrame(this.sortableAutoScrollFrame)
      this.sortableAutoScrollFrame = null
    }

    this.sortablePointerY = null
    this.previewContainerTarget?.classList?.remove("is-sorting")
    this.sortableScrollContainer?.classList?.remove("is-sorting")
    this.sortableScrollContainer = null
    this.sortableAutoScrollActive = false
  }

  handleSortableAutoScrollPointer(event) {
    const source = event?.touches?.[0] || event?.changedTouches?.[0] || event
    if (!source || typeof source.clientY !== "number") return

    this.sortablePointerY = source.clientY
  }

  runSortableAutoScroll() {
    this.sortableAutoScrollFrame = null
    if (!this.sortableAutoScrollActive) return

    const container = this.sortableScrollContainer || this.resolveSortableScrollContainer()
    if (!container || this.sortablePointerY === null || this.sortablePointerY === undefined) {
      this.sortableAutoScrollFrame = window.requestAnimationFrame(() => this.runSortableAutoScroll())
      return
    }

    const rect = container === window
      ? { top: 0, bottom: window.innerHeight, height: window.innerHeight }
      : container.getBoundingClientRect()
    const sensitivity = 156
    const maxSpeed = 34
    let delta = 0

    if (this.sortablePointerY < rect.top + sensitivity) {
      delta = -this.autoScrollSpeed(rect.top + sensitivity - this.sortablePointerY, sensitivity, maxSpeed)
    } else if (this.sortablePointerY > rect.bottom - sensitivity) {
      delta = this.autoScrollSpeed(this.sortablePointerY - (rect.bottom - sensitivity), sensitivity, maxSpeed)
    }

    if (delta !== 0) {
      if (container === window) {
        window.scrollBy({ top: delta, behavior: "auto" })
      } else {
        container.scrollTop += delta
      }
    }

    this.sortableAutoScrollFrame = window.requestAnimationFrame(() => this.runSortableAutoScroll())
  }

  autoScrollSpeed(distance, sensitivity, maxSpeed) {
    const ratio = Math.min(1, Math.max(0, distance / sensitivity))
    return Math.max(6, Math.round(maxSpeed * ratio))
  }

  resolveSortableScrollContainer() {
    if (!this.hasPreviewContainerTarget) return window

    return this.previewContainerTarget.closest(".media-gallery-scroll") ||
      this.previewContainerTarget.closest(".ax-media-modal__body") ||
      this.previewContainerTarget.closest(".ax-media-modal__panel") ||
      this.previewContainerTarget.closest(".habitation-property-main-pane") ||
      window
  }

  updateOrder() {
    if (this.hasOrderInputTarget) {
      const ids = Array.from(this.previewContainerTarget.querySelectorAll('.attached-photo-item'))
      .map(el => el.dataset.id)
      .filter(id => id) // Filter out new uploads (no ID yet) or empty IDs

      this.orderInputTarget.value = ids.join(',')
    }

    if (this.hasApiOrderInputTarget) {
      const apiIndexes = Array.from(this.previewContainerTarget.querySelectorAll('.api-picture-item'))
        .map(el => el.dataset.apiIndex)
        .filter(index => index !== undefined && index !== null && index !== '')

      this.apiOrderInputTarget.value = apiIndexes.join(',')
    }
  }

  setFeatured(event) {
    event.preventDefault()
    event.stopPropagation()

    const item = event.currentTarget.closest('.draggable-item')
    if (!item || !this.hasPreviewContainerTarget) return

    this.previewContainerTarget.prepend(item)
    this.syncNewFilesFromDom()
    this.updateOrder()
    this.refreshPhotoBadges()
    this.syncReorder()
  }

  removeNew(event) {
    event.preventDefault()
    event.stopPropagation()

    const item = event.currentTarget.closest('.new-photo-preview')
    if (!item) return

    const fileId = item.dataset.newFileId
    this.selectedNewFiles = this.selectedNewFiles.filter(entry => entry.id !== fileId)
    item.remove()

    this.syncInputFilesFromState()
    this.clearUploadLimitFeedback()
    this.updateOrder()
    this.refreshPhotoBadges()
  }

  async removeAttached(event) {
    event.preventDefault()
    event.stopPropagation()

    const item = event.currentTarget.closest('.attached-photo-item')
    if (!item || !item.dataset.id) return

    if (this.canSyncDestroy()) {
      const removed = await this.destroyPersistedMedia({ photo_id: item.dataset.id })
      if (!removed) return

      item.remove()
      this.updateOrder()
      this.refreshPhotoBadges()
      return
    }

    if (!this.hasRemovePhotoIdsInputTarget) return

    this.appendHiddenListValue(this.removePhotoIdsInputTarget, item.dataset.id)
    item.hidden = true
    item.remove()

    this.updateOrder()
    this.refreshPhotoBadges()
  }

  async removeApiPicture(event) {
    event.preventDefault()
    event.stopPropagation()

    const item = event.currentTarget.closest('.api-picture-item')
    if (!item || !item.dataset.apiIndex) return

    if (this.canSyncDestroy()) {
      const removed = await this.destroyPersistedMedia({ picture_index: item.dataset.apiIndex })
      if (!removed) return

      item.remove()
      this.updateOrder()
      this.refreshPhotoBadges()
      return
    }

    if (!this.hasRemovePictureIndicesInputTarget) return

    this.appendHiddenListValue(this.removePictureIndicesInputTarget, item.dataset.apiIndex)
    item.hidden = true
    item.remove()

    this.updateOrder()
    this.refreshPhotoBadges()
  }

  toggleSiteVisibility(event) {
    event.preventDefault()
    event.stopPropagation()

    const button = event.currentTarget
    const tile = button.closest('.media-photo-tile')
    if (!tile) return

    const hidden = tile.dataset.siteHidden !== "true"
    tile.dataset.siteHidden = hidden ? "true" : "false"
    tile.classList.toggle('is-site-hidden', hidden)

    if (button.dataset.photoId && this.hasHiddenPhotoIdsInputTarget) {
      this.toggleHiddenListValue(this.hiddenPhotoIdsInputTarget, button.dataset.photoId, hidden)
    }

    if (button.dataset.pictureUrl && this.hasHiddenPictureUrlsInputTarget) {
      this.toggleHiddenListValue(this.hiddenPictureUrlsInputTarget, button.dataset.pictureUrl, hidden)
    }

    this.setSiteToggleButton(button, hidden)
    this.syncVisibility()
  }

  refreshPhotoBadges() {
    const items = Array.from(this.previewContainerTarget.querySelectorAll('.draggable-item'))

    items.forEach((item, index) => {
      const positionBadge = item.querySelector('[data-photo-position-badge]')
      if (positionBadge) positionBadge.textContent = `#${index + 1}`

      const featuredContainer = item.querySelector('[data-photo-featured-control]')
      if (!featuredContainer) return

      if (index === 0) {
        featuredContainer.innerHTML = `
          <span class="ax-media-action ax-media-action--featured is-active" title="Foto em destaque" aria-label="Foto em destaque">
            <i class="bi bi-star-fill"></i>
          </span>
        `
      } else {
        featuredContainer.innerHTML = `
          <button type="button"
                  class="media-photo-feature-button ax-media-action ax-media-action--featured"
                  title="Definir como destaque"
                  aria-label="Definir como destaque"
                  data-action="photo-upload#setFeatured">
            <i class="bi bi-star"></i>
          </button>
        `
      }
    })
  }

  preview(event) {
    const files = Array.from(event.target.files || [])
    const existingFileKeys = new Set(this.selectedNewFiles.map(entry => this.fileKey(entry.file)))
    const newFileEntries = files.filter(file => {
      const key = this.fileKey(file)
      if (existingFileKeys.has(key)) return false

      existingFileKeys.add(key)
      return true
    }).map(file => ({
      id: this.nextNewFileId(),
      file
    }))

    const nextUploadBytes = this.uploadBytesFor(this.selectedNewFiles.concat(newFileEntries))
    if (nextUploadBytes > this.constructor.maxUploadBytes) {
      this.showUploadLimitFeedback(nextUploadBytes)
      this.syncInputFilesFromState()
      return
    }

    this.clearUploadLimitFeedback()
    this.selectedNewFiles = this.selectedNewFiles.concat(newFileEntries)

    if (newFileEntries.length === 0) {
      this.syncInputFilesFromState()
      this.updateOrder()
      this.refreshPhotoBadges()
      return
    }

    newFileEntries.forEach(fileEntry => {
      const file = fileEntry.file
      const imgContainer = document.createElement("div")
      const previewUrl = URL.createObjectURL(file)

      // Match the migrated media grid item and preserve sortable behavior.
      imgContainer.classList.add("ax-media-grid__item", "draggable-item", "new-photo-preview")
      imgContainer.dataset.newFileId = fileEntry.id

      imgContainer.innerHTML = `
        <div class="ax-media-tile__frame media-photo-tile">
          <div class="ax-media-tile__link" title="Pré-visualização de ${this.escapeHtml(file.name)}">
            <img src="${previewUrl}" class="ax-media-tile__image" alt="${this.escapeHtml(file.name)}">
          </div>
          <div class="media-photo-overlay">
            <div class="ax-media-tile__row ax-media-tile__row--top">
              <span class="ax-media-tag ax-media-tag--dark" data-photo-position-badge>#</span>
              <span class="ax-media-tag ax-media-tag--primary">Nova</span>
            </div>
          </div>
        </div>
        <div class="ax-media-tile__footer">
          <div class="ax-media-tile__footer-slot ax-media-tile__footer-slot--left">
            <span data-photo-featured-control>
              <button type="button"
                      class="media-photo-feature-button ax-media-action ax-media-action--featured"
                      title="Definir como destaque"
                      aria-label="Definir como destaque"
                      data-action="photo-upload#setFeatured">
                <i class="bi bi-star"></i>
              </button>
            </span>
          </div>
          <div class="ax-media-tile__footer-slot ax-media-tile__footer-slot--right">
            <span class="ax-media-action-group">
              <button type="button" class="media-photo-drag-handle media-photo-action-button ax-media-action ax-media-action--neutral" title="Arrastar para reordenar" aria-label="Arrastar para reordenar">
                <i class="bi bi-grip-vertical"></i>
              </button>
              <button type="button"
                      class="media-photo-action-button ax-media-action ax-media-action--danger"
                      title="Remover foto selecionada"
                      aria-label="Remover foto selecionada"
                      data-action="photo-upload#removeNew">
                <i class="bi bi-trash"></i>
              </button>
            </span>
          </div>
        </div>
      `
      this.previewContainerTarget.appendChild(imgContainer)
    })

    this.syncInputFilesFromState()
    this.updateOrder()
    this.refreshPhotoBadges()
    this.uploadNewFiles(newFileEntries)
  }

  handleFormSubmit(event) {
    const uploadBytes = this.uploadBytesFor(this.selectedNewFiles)
    if (uploadBytes > this.constructor.maxUploadBytes) {
      event.preventDefault()
      event.stopImmediatePropagation()
      this.showUploadLimitFeedback(uploadBytes)
      return
    }

    if (!this.shouldSubmitFormAsync(event)) return

    event.preventDefault()
    event.stopImmediatePropagation()
    this.submitMediaForm()
  }

  syncNewFilesFromDom() {
    if (!this.hasPreviewContainerTarget || this.selectedNewFiles.length === 0) return

    const byId = new Map(this.selectedNewFiles.map(entry => [entry.id, entry]))
    const orderedIds = Array.from(this.previewContainerTarget.querySelectorAll('.new-photo-preview'))
      .map(el => el.dataset.newFileId)
      .filter(id => byId.has(id))

    this.selectedNewFiles = orderedIds.map(id => byId.get(id))
    this.syncInputFilesFromState()
  }

  syncInputFilesFromState() {
    if (!this.hasInputTarget || typeof DataTransfer === "undefined") return

    const dataTransfer = new DataTransfer()
    this.selectedNewFiles.forEach(entry => dataTransfer.items.add(entry.file))
    this.inputTarget.files = dataTransfer.files
  }

  appendHiddenListValue(input, value) {
    if (!input || !value) return

    const values = input.value
      .split(',')
      .map(item => item.trim())
      .filter(Boolean)

    if (!values.includes(value)) values.push(value)
    input.value = values.join(',')
  }

  toggleHiddenListValue(input, value, hidden) {
    if (!input || !value) return

    const values = input.value
      .split(',')
      .map(item => item.trim())
      .filter(Boolean)

    const nextValues = hidden
      ? Array.from(new Set(values.concat(value)))
      : values.filter(item => item !== value)

    input.value = nextValues.join(',')
  }

  setSiteToggleButton(button, hidden) {
    button.classList.toggle('ax-media-action--published', !hidden)
    button.classList.toggle('ax-media-action--neutral', hidden)
    button.title = hidden ? 'Foto interna, fora do site' : 'Foto publicada no site'
    button.setAttribute('aria-label', button.title)

    const icon = button.querySelector('i')
    if (icon) {
      icon.classList.toggle('bi-globe2', !hidden)
      icon.classList.toggle('bi-eye-slash', hidden)
    }

    const label = button.querySelector('span')
    if (label) label.textContent = hidden ? 'Interna' : 'Site'
  }

  nextNewFileId() {
    this.newFileIdCounter += 1
    return `new-photo-${Date.now()}-${this.newFileIdCounter}`
  }

  fileKey(file) {
    return [file.name, file.size, file.lastModified].join(':')
  }

  uploadBytesFor(entries) {
    return entries.reduce((total, entry) => total + Number(entry.file?.size || 0), 0)
  }

  showUploadLimitFeedback(totalBytes = this.uploadBytesFor(this.selectedNewFiles)) {
    const message = `As novas fotos selecionadas somam ${this.formatBytes(totalBytes)}. Envie no máximo ${this.formatBytes(this.constructor.maxUploadBytes)} por vez.`
    this.showMediaTab()

    if (this.hasUploadLimitFeedbackTarget) {
      this.uploadLimitFeedbackTarget.textContent = message
      this.uploadLimitFeedbackTarget.hidden = false
    } else {
      const feedback = this.ensureUploadLimitFeedback()
      feedback.textContent = message
      feedback.hidden = false
    }

    if (this.hasInputTarget) this.inputTarget.value = ""
    this.element.scrollIntoView({ behavior: "smooth", block: "center" })
  }

  showMediaTab() {
    const panel = this.element.closest(".tab-pane")
    if (!panel?.id) return

    const escapedId = CSS.escape(panel.id)
    const tabButton = document.querySelector(`[data-ax-tabs-target-param="#${escapedId}"], [data-bs-target="#${escapedId}"]`)

    if (tabButton) tabButton.click()
  }

  clearUploadLimitFeedback() {
    const feedback = this.hasUploadLimitFeedbackTarget ? this.uploadLimitFeedbackTarget : this.fallbackUploadLimitFeedback
    if (!feedback) return

    feedback.textContent = ""
    feedback.hidden = true
    feedback.classList.remove("is-error", "is-success")
  }

  async uploadNewFiles(fileEntries) {
    if (!this.canSyncUpload() || fileEntries.length === 0) return
    if (this.uploadInProgress) return

    this.uploadInProgress = true
    this.setBusyState(true)
    this.showProgressFeedback("Preparando envio das fotos...", 1)

    const formData = new FormData()
    fileEntries.forEach(entry => formData.append("habitation[photos][]", entry.file))

    const watermarkInput = this.element.querySelector('input[name="habitation[apply_photo_watermark]"][type="checkbox"]')
    if (watermarkInput) {
      formData.append("habitation[apply_photo_watermark]", watermarkInput.checked ? "1" : "0")
    }

    try {
      const response = await this.requestJsonWithProgress(this.uploadUrlValue, {
        method: "POST",
        body: formData,
        onProgress: (percent) => {
          this.showProgressFeedback(`Enviando fotos... ${percent}%`, percent)
        }
      })

      this.selectedNewFiles = []
      if (this.hasInputTarget) this.inputTarget.value = ""
      this.applyMediaPayload(response, { scrollToEnd: true })
      this.showProgressFeedback(response.message || "Fotos enviadas com sucesso.", 100, "success")
      this.hideProgressLater()
    } catch (error) {
      this.showProgressFeedback(error.message || "Não foi possível enviar as fotos agora.", 100, "error")
    } finally {
      this.uploadInProgress = false
      this.setBusyState(false)
    }
  }

  async submitMediaForm() {
    if (!this.form || this.formSubmitInProgress) return

    if (this.uploadInProgress) {
      this.showTransientFeedback("Aguarde o envio das fotos terminar antes de salvar.", true)
      return
    }

    this.syncNewFilesFromDom()
    this.updateOrder()

    this.formSubmitInProgress = true
    this.setBusyState(true)
    this.showProgressFeedback("Salvando mídia...", 8)

    try {
      const response = await this.requestJsonWithProgress(this.form.action, {
        method: this.resolvedFormMethod(),
        body: new FormData(this.form),
        onProgress: (percent) => {
          this.showProgressFeedback(`Salvando mídia... ${percent}%`, percent)
        }
      })

      this.selectedNewFiles = []
      if (this.hasInputTarget) this.inputTarget.value = ""
      this.applyMediaPayload(response)
      this.showProgressFeedback(response.message || "Mídia salva com sucesso.", 100, "success")
      this.hideProgressLater()
    } catch (error) {
      this.showProgressFeedback(error.message || "Não foi possível salvar a mídia agora.", 100, "error")
    } finally {
      this.formSubmitInProgress = false
      this.setBusyState(false)
    }
  }

  async syncReorder() {
    if (!this.canSyncReorder()) return

    try {
      const response = await this.requestJson(this.reorderUrlValue, {
        method: "PATCH",
        json: {
          habitation: {
            ordered_photo_ids: this.hasOrderInputTarget ? this.orderInputTarget.value : "",
            ordered_picture_indices: this.hasApiOrderInputTarget ? this.apiOrderInputTarget.value : ""
          }
        }
      })
      this.applyMediaPayload(response, { replaceGallery: false })
    } catch (error) {
      this.showTransientFeedback(error.message || "Não foi possível salvar a ordem das fotos.", true)
    }
  }

  async syncVisibility() {
    if (!this.canSyncVisibility()) return

    try {
      const response = await this.requestJson(this.visibilityUrlValue, {
        method: "PATCH",
        json: {
          habitation: {
            site_hidden_photo_ids: this.hasHiddenPhotoIdsInputTarget ? this.hiddenPhotoIdsInputTarget.value : "",
            site_hidden_picture_urls: this.hasHiddenPictureUrlsInputTarget ? this.hiddenPictureUrlsInputTarget.value : ""
          }
        }
      })
      this.applyMediaPayload(response, { replaceGallery: false })
    } catch (error) {
      this.showTransientFeedback(error.message || "Não foi possível salvar a visibilidade da foto.", true)
    }
  }

  async destroyPersistedMedia(payload) {
    try {
      const response = await this.requestJson(this.destroyUrlValue, {
        method: "DELETE",
        json: payload
      })
      this.applyMediaPayload(response)
      this.showTransientFeedback(response.message || "Foto removida.")
      return true
    } catch (error) {
      this.showTransientFeedback(error.message || "Não foi possível remover a foto.", true)
      return false
    }
  }

  async requestJson(url, options = {}) {
    const headers = {
      "Accept": "application/json",
      "X-Requested-With": "XMLHttpRequest"
    }
    const csrfToken = this.csrfToken()
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken

    const requestOptions = {
      method: options.method || "GET",
      headers
    }

    if (options.body) {
      requestOptions.body = options.body
    } else if (options.json) {
      requestOptions.body = JSON.stringify(options.json)
      requestOptions.headers["Content-Type"] = "application/json"
    }

    const response = await fetch(url, requestOptions)
    const contentType = response.headers.get("content-type") || ""
    const payload = contentType.includes("application/json") ? await response.json() : {}

    if (!response.ok || payload.ok === false) {
      const message = payload.error || (Array.isArray(payload.errors) ? payload.errors.join(", ") : null)
      throw new Error(message || "A operação de mídia não pôde ser concluída.")
    }

    return payload
  }

  requestJsonWithProgress(url, options = {}) {
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest()
      xhr.open(options.method || "GET", url, true)
      xhr.setRequestHeader("Accept", "application/json")
      xhr.setRequestHeader("X-Requested-With", "XMLHttpRequest")

      const csrfToken = this.csrfToken()
      if (csrfToken) xhr.setRequestHeader("X-CSRF-Token", csrfToken)
      if (options.json) xhr.setRequestHeader("Content-Type", "application/json")

      xhr.upload.onprogress = (event) => {
        if (!event.lengthComputable || typeof options.onProgress !== "function") return

        const percent = Math.max(1, Math.min(95, Math.round((event.loaded / event.total) * 95)))
        options.onProgress(percent)
      }

      xhr.onload = () => {
        const payload = this.parseJsonResponse(xhr.responseText)

        if (xhr.status < 200 || xhr.status >= 300 || payload.ok === false) {
          const message = payload.error || (Array.isArray(payload.errors) ? payload.errors.join(", ") : null)
          reject(new Error(message || "A operação de mídia não pôde ser concluída."))
          return
        }

        if (typeof options.onProgress === "function") options.onProgress(100)
        resolve(payload)
      }

      xhr.onerror = () => reject(new Error("Não foi possível conectar ao servidor."))
      xhr.ontimeout = () => reject(new Error("Tempo limite ao salvar mídia."))
      xhr.timeout = options.timeout || 120000

      xhr.send(options.json ? JSON.stringify(options.json) : options.body)
    })
  }

  parseJsonResponse(value) {
    if (!value) return {}

    try {
      return JSON.parse(value)
    } catch (_error) {
      return {}
    }
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  canSyncUpload() {
    return this.asyncValue && this.hasUploadUrlValue
  }

  canSyncReorder() {
    return this.asyncValue && this.hasReorderUrlValue
  }

  canSyncVisibility() {
    return this.asyncValue && this.hasVisibilityUrlValue
  }

  canSyncDestroy() {
    return this.asyncValue && this.hasDestroyUrlValue
  }

  shouldSubmitFormAsync(event) {
    return Boolean(
      this.asyncValue &&
      this.form &&
      event.target === this.form &&
      this.form.dataset.photoUploadAsyncSubmit === "true"
    )
  }

  resolvedFormMethod() {
    return (this.form?.method || "POST").toUpperCase()
  }

  applyMediaPayload(payload, options = {}) {
    const replaceGallery = options.replaceGallery !== false

    if (replaceGallery && typeof payload.gallery_html === "string" && this.hasPreviewContainerTarget) {
      this.previewContainerTarget.innerHTML = payload.gallery_html
    }

    if (payload.inputs) {
      if (this.hasOrderInputTarget && payload.inputs.ordered_photo_ids !== undefined) {
        this.orderInputTarget.value = payload.inputs.ordered_photo_ids || ""
      }
      if (this.hasApiOrderInputTarget && payload.inputs.ordered_picture_indices !== undefined) {
        this.apiOrderInputTarget.value = payload.inputs.ordered_picture_indices || ""
      }
      if (this.hasHiddenPhotoIdsInputTarget && payload.inputs.site_hidden_photo_ids !== undefined) {
        this.hiddenPhotoIdsInputTarget.value = payload.inputs.site_hidden_photo_ids || ""
      }
      if (this.hasHiddenPictureUrlsInputTarget && payload.inputs.site_hidden_picture_urls !== undefined) {
        this.hiddenPictureUrlsInputTarget.value = payload.inputs.site_hidden_picture_urls || ""
      }
    }

    if (this.hasRemovePhotoIdsInputTarget) this.removePhotoIdsInputTarget.value = ""
    if (this.hasRemovePictureIndicesInputTarget) this.removePictureIndicesInputTarget.value = ""

    this.updateOrder()
    this.refreshPhotoBadges()
    this.updateMediaCounts(payload.counts)
    if (options.scrollToEnd) this.scrollGalleryToEnd()
  }

  showTransientFeedback(message, isError = false) {
    const feedback = this.hasUploadLimitFeedbackTarget ? this.uploadLimitFeedbackTarget : this.ensureUploadLimitFeedback()
    feedback.textContent = message
    feedback.hidden = false
    feedback.classList.toggle("is-error", isError)

    window.clearTimeout(this.feedbackTimeout)
    this.feedbackTimeout = window.setTimeout(() => {
      feedback.textContent = ""
      feedback.hidden = true
      feedback.classList.remove("is-error")
    }, isError ? 6000 : 2500)
  }

  showProgressFeedback(message, percent = 0, state = "active") {
    const feedback = this.hasUploadLimitFeedbackTarget ? this.uploadLimitFeedbackTarget : this.ensureUploadLimitFeedback()
    const safePercent = Math.max(0, Math.min(100, Math.round(percent || 0)))
    const isError = state === "error"
    const isSuccess = state === "success"

    window.clearTimeout(this.feedbackTimeout)
    feedback.hidden = false
    feedback.classList.toggle("is-error", isError)
    feedback.classList.toggle("is-success", isSuccess)
    feedback.innerHTML = `
      <div class="ax-media-upload-progress" role="status" aria-live="polite">
        <div class="ax-upload-progress__header">
          <span>${this.escapeHtml(message)}</span>
          <strong>${safePercent}%</strong>
        </div>
        <div class="ax-progress ax-upload-progress__bar">
          <i class="${isError ? "ax-upload-progress__fill--danger" : isSuccess ? "ax-upload-progress__fill--success" : ""}" style="width:${safePercent}%"></i>
        </div>
      </div>
    `
  }

  hideProgressLater(delay = 3000) {
    const feedback = this.hasUploadLimitFeedbackTarget ? this.uploadLimitFeedbackTarget : this.fallbackUploadLimitFeedback
    if (!feedback) return

    window.clearTimeout(this.feedbackTimeout)
    this.feedbackTimeout = window.setTimeout(() => {
      feedback.textContent = ""
      feedback.hidden = true
      feedback.classList.remove("is-error", "is-success")
    }, delay)
  }

  setBusyState(isBusy) {
    this.element.classList.toggle("is-saving-media", isBusy)

    if (!this.form) return

    this.form.querySelectorAll('button[type="submit"], input[type="submit"]').forEach((button) => {
      button.disabled = isBusy
      button.classList.toggle("is-loading", isBusy)
    })
  }

  updateMediaCounts(counts) {
    if (!counts || counts.total === undefined || counts.total === null) return

    const total = Number(counts.total)
    if (!Number.isFinite(total)) return

    const label = `${total} ${total === 1 ? "item" : "itens"}`
    const linkedLabel = `${total} ${total === 1 ? "item vinculado" : "itens vinculados"}`

    this.element.querySelectorAll(".ax-media-organizer__count").forEach((element) => {
      element.textContent = label
    })

    this.element.querySelectorAll(".ax-media-toolbar__title span").forEach((element) => {
      element.textContent = linkedLabel
    })

    this.form?.querySelectorAll(".ax-media-modal__footer-meta span").forEach((element) => {
      element.textContent = `${total} mídia(s) vinculada(s)`
    })
  }

  scrollGalleryToEnd() {
    const scroller = this.previewContainerTarget?.closest(".media-gallery-scroll")
    if (!scroller) return

    window.requestAnimationFrame(() => {
      scroller.scrollTo({ top: scroller.scrollHeight, behavior: "smooth" })
    })
  }

  ensureUploadLimitFeedback() {
    if (this.fallbackUploadLimitFeedback) return this.fallbackUploadLimitFeedback

    const feedback = document.createElement("div")
    feedback.className = "ax-media-upload-panel__feedback"
    feedback.hidden = true
    this.element.prepend(feedback)
    this.fallbackUploadLimitFeedback = feedback
    return feedback
  }

  formatBytes(bytes) {
    return `${(bytes / (1024 * 1024)).toLocaleString("pt-BR", { maximumFractionDigits: 1 })} MB`
  }

  escapeHtml(value) {
    const span = document.createElement("span")
    span.textContent = value || ""
    return span.innerHTML
  }
}
