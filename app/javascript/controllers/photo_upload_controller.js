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

  static maxUploadBytes = 250 * 1024 * 1024

  connect() {
    this.selectedNewFiles = []
    this.newFileIdCounter = 0
    this.boundHandleDragOver = this.handleDragOver.bind(this)
    this.boundHandleDrop = this.handleDrop.bind(this)
    this.boundHandleDragLeave = this.handleDragLeave.bind(this)
    this.boundValidateSubmit = this.validateSubmit.bind(this)
    this.form = this.element.closest('form')

    this.initSortable()

    // Drag and Drop
    this.element.addEventListener('dragover', this.boundHandleDragOver)
    this.element.addEventListener('drop', this.boundHandleDrop)
    this.element.addEventListener('dragleave', this.boundHandleDragLeave)
    if (this.form) this.form.addEventListener('submit', this.boundValidateSubmit, true)
  }

  disconnect() {
    if (this.sortable) this.sortable.destroy()
    this.element.removeEventListener('dragover', this.boundHandleDragOver)
    this.element.removeEventListener('drop', this.boundHandleDrop)
    this.element.removeEventListener('dragleave', this.boundHandleDragLeave)
    if (this.form) this.form.removeEventListener('submit', this.boundValidateSubmit, true)
  }

  handleDragOver(e) {
    e.preventDefault()
    e.stopPropagation()
    this.element.classList.add('border-primary', 'bg-light-subtle')
  }

  handleDragLeave(e) {
    e.preventDefault()
    this.element.classList.remove('border-primary', 'bg-light-subtle')
  }

  handleDrop(e) {
    e.preventDefault()
    e.stopPropagation()
    this.element.classList.remove('border-primary', 'bg-light-subtle')

    if (e.dataTransfer && e.dataTransfer.files.length > 0) {
      if (this.hasInputTarget) {
        this.inputTarget.files = e.dataTransfer.files
        // Trigger change event to run preview
        this.inputTarget.dispatchEvent(new Event('change'))
      }
    }
  }

  initSortable() {
    // Only initialize if container exists
    if (!this.hasPreviewContainerTarget) return

    this.sortable = new Sortable(this.previewContainerTarget, {
      animation: 150,
      ghostClass: 'sortable-ghost',
      handle: '.media-photo-drag-handle',
      draggable: '.draggable-item',
      onEnd: (evt) => {
        this.syncNewFilesFromDom()
        this.updateOrder()
        this.refreshPhotoBadges()
      }
    })
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

  removeAttached(event) {
    event.preventDefault()
    event.stopPropagation()

    const item = event.currentTarget.closest('.attached-photo-item')
    if (!item || !item.dataset.id) return
    if (!this.hasRemovePhotoIdsInputTarget) return

    this.appendHiddenListValue(this.removePhotoIdsInputTarget, item.dataset.id)
    item.classList.add('d-none')
    item.remove()

    this.updateOrder()
    this.refreshPhotoBadges()
  }

  removeApiPicture(event) {
    event.preventDefault()
    event.stopPropagation()

    const item = event.currentTarget.closest('.api-picture-item')
    if (!item || !item.dataset.apiIndex) return
    if (!this.hasRemovePictureIndicesInputTarget) return

    this.appendHiddenListValue(this.removePictureIndicesInputTarget, item.dataset.apiIndex)
    item.classList.add('d-none')
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
          <span class="badge bg-warning text-dark border shadow-sm">
            <i class="bi bi-star-fill me-1"></i>Destaque
          </span>
        `
      } else {
        featuredContainer.innerHTML = `
          <button type="button"
                  class="media-photo-feature-button btn btn-sm btn-warning border py-0 px-1 fw-semibold"
                  title="Definir como destaque"
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

      // Match standard column classes and add draggable-item
      imgContainer.classList.add("col-6", "col-md-3", "col-lg-2", "draggable-item", "new-photo-preview")
      imgContainer.dataset.newFileId = fileEntry.id

      imgContainer.innerHTML = `
        <div class="position-relative ratio ratio-1x1 group-hover media-photo-tile">
          <img src="${previewUrl}" class="rounded border object-fit-cover w-100 h-100" alt="${this.escapeHtml(file.name)}">
          <div class="media-photo-overlay position-absolute d-flex flex-column justify-content-between p-1">
            <div class="d-flex justify-content-between align-items-start gap-1">
              <span class="badge bg-dark bg-opacity-75 border shadow-sm" data-photo-position-badge>#</span>
              <span class="badge bg-success border shadow-sm">Nova</span>
            </div>
            <div class="d-flex justify-content-between align-items-end gap-1">
              <span data-photo-featured-control>
                <button type="button"
                        class="media-photo-feature-button btn btn-sm btn-warning border py-0 px-1 fw-semibold"
                        title="Definir como destaque"
                        data-action="photo-upload#setFeatured">
                  <i class="bi bi-star"></i>
                </button>
              </span>
              <span class="d-flex align-items-center gap-1">
                <button type="button"
                        class="btn btn-sm btn-danger border py-0 px-1"
                        title="Remover foto selecionada"
                        data-action="photo-upload#removeNew">
                  <i class="bi bi-trash"></i>
                </button>
                <button type="button" class="media-photo-drag-handle btn btn-sm btn-light border py-0 px-1" title="Arrastar foto">
                  <i class="bi bi-grip-vertical"></i>
                </button>
              </span>
            </div>
          </div>
        </div>
      `
      this.previewContainerTarget.appendChild(imgContainer)
    })

    this.syncInputFilesFromState()
    this.updateOrder()
    this.refreshPhotoBadges()
  }

  validateSubmit(event) {
    if (this.uploadBytesFor(this.selectedNewFiles) <= this.constructor.maxUploadBytes) return

    event.preventDefault()
    event.stopImmediatePropagation()
    this.showUploadLimitFeedback()
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
    button.classList.toggle('btn-success', !hidden)
    button.classList.toggle('btn-secondary', hidden)
    button.title = hidden ? 'Foto interna, fora do site' : 'Foto publicada no site'

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

    if (this.hasUploadLimitFeedbackTarget) {
      this.uploadLimitFeedbackTarget.textContent = message
      this.uploadLimitFeedbackTarget.classList.remove('d-none')
    } else {
      window.alert(message)
    }

    if (this.hasInputTarget) this.inputTarget.value = ""
    this.element.scrollIntoView({ behavior: "smooth", block: "center" })
  }

  clearUploadLimitFeedback() {
    if (!this.hasUploadLimitFeedbackTarget) return

    this.uploadLimitFeedbackTarget.textContent = ""
    this.uploadLimitFeedbackTarget.classList.add('d-none')
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
