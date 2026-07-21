import { Controller } from "@hotwired/stimulus"
import { combine } from "@atlaskit/pragmatic-drag-and-drop/combine"
import {
  draggable,
  dropTargetForElements,
  monitorForElements
} from "@atlaskit/pragmatic-drag-and-drop/element/adapter"

// Calibração do arraste de reordenação de fotos.
//
// MODELO: grade congelada. Durante o arraste NADA se move — o tile de origem
// continua ocupando o próprio espaço (vira placeholder tracejado) e as demais
// fotos ficam paradas. O destino é comunicado por uma barra vertical entre os
// tiles, e a reordenação real acontece UMA vez, no drop. Isso elimina o antigo
// efeito de "fotos correndo de um lado pro outro", em que o reflow movia os
// tiles sob o ponteiro parado e o alvo oscilava sozinho.
const MEDIA_DRAG_TUNING = {
  // Fração da largura do tile que o ponteiro precisa ultrapassar para a barra
  // ir do lado esquerdo para o direito (0.5 = exatamente o meio).
  insertAfterFraction: 0.5,
  // Metade da calha entre tiles: onde a barra é desenhada.
  indicatorGapPx: 6,
  // Animação de reacomodação das fotos depois do drop (FLIP).
  reorderAnimationMs: 170,
  reorderAnimationEasing: "cubic-bezier(.2, .8, .2, 1)"
}

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
    this.boundCaptureMediaPointerDown = this.prepareMediaPointerIntent.bind(this)
    this.boundSuppressMediaClickAfterDrag = this.suppressMediaClickAfterDrag.bind(this)
    this.form = this.element.closest('form')
    this.mediaDragState = null
    this.dragAllowedItem = null
    this.recentlyReorderedMedia = false

    this.initMediaDragAndDrop()
    this.syncSiteVisibilityControls()

    // Drag and Drop
    this.element.addEventListener("pointerdown", this.boundCaptureMediaPointerDown, true)
    this.element.addEventListener("click", this.boundSuppressMediaClickAfterDrag, true)
    this.element.addEventListener('dragover', this.boundHandleDragOver)
    this.element.addEventListener('drop', this.boundHandleDrop)
    this.element.addEventListener('dragleave', this.boundHandleDragLeave)
    if (this.form) this.form.addEventListener('submit', this.boundHandleFormSubmit, true)
  }

  disconnect() {
    this.cleanupMediaDragAndDrop?.()
    this.stopSortableAutoScroll()
    this.element.removeEventListener("pointerdown", this.boundCaptureMediaPointerDown, true)
    this.element.removeEventListener("click", this.boundSuppressMediaClickAfterDrag, true)
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

  initMediaDragAndDrop() {
    if (!this.hasPreviewContainerTarget) return

    this.cleanupMediaDragAndDrop?.()
    this.cleanupMediaDragAndDrop = combine(
      this.registerMediaGrid(this.previewContainerTarget),
      ...this.mediaDragItems().map((item) => this.registerMediaItem(item)),
      monitorForElements({
        canMonitor: ({ source }) => this.isMediaDragSource(source),
        onDrag: ({ source, location }) => this.moveMediaItemWithPointer(source, location),
        onDropTargetChange: ({ source, location }) => this.moveMediaItemWithPointer(source, location),
        onDrop: ({ source }) => this.handleMediaDrop(source)
      })
    )
  }

  refreshMediaDragAndDrop() {
    this.cleanupMediaDragAndDrop?.()
    this.cleanupMediaDragAndDrop = null
    this.initMediaDragAndDrop()
  }

  registerMediaGrid(grid) {
    return dropTargetForElements({
      element: grid,
      canDrop: ({ source }) => this.isMediaDragSource(source),
      getData: () => ({ type: "media-grid" }),
      getIsSticky: () => true
    })
  }

  registerMediaItem(item) {
    return draggable({
      element: item,
      canDrag: () => this.dragAllowedItem === item,
      getInitialData: () => ({ type: "media-item" }),
      onDragStart: () => this.beginMediaDrag(item)
      // O drop é tratado só no monitor: o adapter despacha onDrop primeiro no
      // draggable e só depois no monitor, e a limpeza zera o mediaDragState —
      // que é justamente o que o commit precisa ler.
    })
  }

  mediaDragItems() {
    if (!this.hasPreviewContainerTarget) return []

    return Array.from(this.previewContainerTarget.querySelectorAll(".draggable-item"))
  }

  beginMediaDrag(item) {
    const items = this.mediaDragItems()
    const dragIndex = items.indexOf(item)
    this.mediaDragState = {
      item,
      items,
      // Geometria congelada no início do arraste, em coordenadas RELATIVAS ao
      // container. Como nada se move até o drop, ela continua válida o arraste
      // inteiro — inclusive durante o autoscroll, já que o retângulo do
      // container é relido a cada movimento. Custo: N rects uma única vez.
      rects: this.captureMediaLayout(items),
      dragIndex,
      // Começa em "fica onde está": a barra já nasce na borda esquerda do
      // próprio tile, então nunca há um frame sem indicação de destino.
      insertionIndex: dragIndex
    }
    item.classList.add("sortable-ghost")
    this.previewContainerTarget.classList.add("is-sorting")
    this.positionMediaDropIndicator(this.mediaDragState.rects[dragIndex], false)
    this.startSortableAutoScroll()
  }

  finishMediaDrag(item) {
    this.cancelPendingMediaMove()
    item?.classList.remove("sortable-ghost")
    this.previewContainerTarget?.classList?.remove("is-sorting")
    this.hideMediaDropIndicator()
    this.stopSortableAutoScroll()
    window.setTimeout(() => {
      this.recentlyReorderedMedia = false
    }, 120)
  }

  cancelPendingMediaMove() {
    if (this.mediaMoveFrame) {
      window.cancelAnimationFrame(this.mediaMoveFrame)
      this.mediaMoveFrame = null
    }
    this.pendingMediaMove = null
  }

  moveMediaItemWithPointer(source, location) {
    if (!this.isMediaDragSource(source) || !this.hasPreviewContainerTarget) return

    const input = location?.current?.input
    if (!input) return

    // Autoscroll acompanha o ponteiro imediatamente (barato). O recálculo do
    // destino é coalescido para 1x por frame — sem isso o onDrag dispararia
    // dezenas de vezes por frame e o arraste travava.
    this.handleSortableAutoScrollPointer(input)

    this.pendingMediaMove = { clientX: input.clientX, clientY: input.clientY }
    if (this.mediaMoveFrame) return
    this.mediaMoveFrame = window.requestAnimationFrame(() => {
      this.mediaMoveFrame = null
      const pending = this.pendingMediaMove
      this.pendingMediaMove = null
      if (pending && this.mediaDragState) {
        this.applyMediaPointerMove(pending.clientX, pending.clientY)
      }
    })
  }

  // Só decide o destino e move a barra. NÃO toca na ordem do DOM: a grade
  // permanece exatamente como estava até o usuário soltar.
  applyMediaPointerMove(clientX, clientY) {
    const state = this.mediaDragState
    if (!state || !this.hasPreviewContainerTarget) return

    const containerRect = this.previewContainerTarget.getBoundingClientRect()
    const pointerX = clientX - containerRect.left
    const pointerY = clientY - containerRect.top

    const target = this.closestMediaRectForPointer(state.rects, pointerX, pointerY)
    if (!target) return

    const insertAfter = pointerX >= target.left + target.width * MEDIA_DRAG_TUNING.insertAfterFraction
    state.insertionIndex = target.index + (insertAfter ? 1 : 0)
    this.positionMediaDropIndicator(target, insertAfter)
  }

  // Tile mais próximo do ponteiro pela distância até o retângulo (0 se dentro).
  // Com a grade parada, o "mais próximo" é sempre estável — não precisa de
  // margens de tolerância nem de histerese para evitar oscilação.
  closestMediaRectForPointer(rects, pointerX, pointerY) {
    return rects.reduce((best, rect) => {
      const dx = Math.max(rect.left - pointerX, 0, pointerX - rect.right)
      const dy = Math.max(rect.top - pointerY, 0, pointerY - rect.bottom)
      const distance = Math.hypot(dx, dy)

      if (!best || distance < best.distance) return { ...rect, distance }
      return best
    }, null)
  }

  // Ordem importa: commita a inserção enquanto o mediaDragState ainda existe e
  // só então limpa o arraste (que zera esse estado).
  handleMediaDrop(source) {
    if (!this.isMediaDragSource(source)) return

    const item = this.mediaDragState?.item || source.element
    this.commitMediaDrop()
    this.finishMediaDrag(item)
  }

  commitMediaDrop() {
    if (!this.mediaDragState) return

    this.cancelPendingMediaMove()
    // Tira a barra antes de mexer no DOM para ela nunca virar filha "solta" da
    // grade no meio da inserção.
    this.hideMediaDropIndicator()
    const reordered = this.applyMediaInsertion()
    // Suprime o clique pós-arraste mesmo sem mudança (senão soltar em cima da
    // própria foto abriria o modal), mas só persiste se a ordem mudou.
    this.recentlyReorderedMedia = true
    if (!reordered) return

    this.syncNewFilesFromDom()
    this.updateOrder()
    this.refreshPhotoBadges()
    this.syncReorder()
  }

  // A ÚNICA mutação de ordem do arraste inteiro, executada no drop.
  applyMediaInsertion() {
    const state = this.mediaDragState
    if (!state || state.insertionIndex === null) return false

    const { item, items, dragIndex, insertionIndex } = state
    // insertionIndex é a fronteira entre tiles: as duas fronteiras vizinhas ao
    // próprio tile arrastado significam "ficar onde está".
    if (insertionIndex === dragIndex || insertionIndex === dragIndex + 1) return false

    const previousRects = this.captureMediaItemRects()
    const reference = items[insertionIndex] || null
    if (reference) {
      this.previewContainerTarget.insertBefore(item, reference)
    } else {
      this.previewContainerTarget.appendChild(item)
    }
    this.animateMediaReorder(previousRects, item)

    return true
  }

  mediaDropIndicator() {
    if (this.mediaDropIndicatorElement?.isConnected) return this.mediaDropIndicatorElement

    const indicator = document.createElement("div")
    indicator.className = "ax-media-drop-indicator"
    indicator.setAttribute("aria-hidden", "true")
    // Sem transição no primeiro posicionamento: senão a barra "voaria" do
    // canto da grade até o tile de origem ao começar o arraste.
    indicator.style.transition = "none"
    this.previewContainerTarget.appendChild(indicator)
    this.mediaDropIndicatorElement = indicator
    window.requestAnimationFrame(() => { indicator.style.transition = "" })

    return indicator
  }

  hideMediaDropIndicator() {
    this.mediaDropIndicatorElement?.remove()
    this.mediaDropIndicatorElement = null
  }

  positionMediaDropIndicator(rect, insertAfter) {
    if (!rect) return

    const gap = MEDIA_DRAG_TUNING.indicatorGapPx
    const indicator = this.mediaDropIndicator()
    const x = insertAfter ? rect.right + gap : rect.left - gap

    indicator.style.transform = `translate(${Math.round(x)}px, ${Math.round(rect.top)}px)`
    indicator.style.height = `${Math.round(rect.height)}px`
  }

  // Retângulos relativos ao container (imunes a scroll da página).
  captureMediaLayout(items) {
    const containerRect = this.previewContainerTarget.getBoundingClientRect()

    return items.map((item, index) => {
      const rect = item.getBoundingClientRect()

      return {
        index,
        left: rect.left - containerRect.left,
        right: rect.right - containerRect.left,
        top: rect.top - containerRect.top,
        bottom: rect.bottom - containerRect.top,
        width: rect.width,
        height: rect.height
      }
    })
  }

  captureMediaItemRects() {
    return new Map(this.mediaDragItems().map((item) => [item, item.getBoundingClientRect()]))
  }

  animateMediaReorder(previousRects, draggedItem) {
    if (window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches) return

    this.mediaDragItems().forEach((item) => {
      if (item === draggedItem) return

      const previousRect = previousRects.get(item)
      if (!previousRect) return

      const currentRect = item.getBoundingClientRect()
      const deltaX = previousRect.left - currentRect.left
      const deltaY = previousRect.top - currentRect.top
      if (Math.abs(deltaX) < 1 && Math.abs(deltaY) < 1) return

      item.getAnimations?.().forEach((animation) => animation.cancel())
      item.animate(
        [
          { transform: `translate(${deltaX}px, ${deltaY}px)` },
          { transform: "translate(0, 0)" }
        ],
        {
          duration: MEDIA_DRAG_TUNING.reorderAnimationMs,
          easing: MEDIA_DRAG_TUNING.reorderAnimationEasing,
          fill: "both"
        }
      )
    })
  }

  prepareMediaPointerIntent(event) {
    const item = event.target.closest(".draggable-item")
    if (!item) {
      this.dragAllowedItem = null
      return
    }

    const handle = event.target.closest(".media-photo-drag-handle")
    this.dragAllowedItem = handle && item.contains(handle) ? item : null
  }

  isMediaDragSource(source) {
    return source?.data?.type === "media-item" && source?.element?.classList?.contains("draggable-item")
  }

  suppressMediaClickAfterDrag(event) {
    if (!this.recentlyReorderedMedia) return
    if (!event.target.closest(".draggable-item")) return

    event.preventDefault()
    event.stopImmediatePropagation()
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

    if (this.mediaMoveFrame) {
      window.cancelAnimationFrame(this.mediaMoveFrame)
      this.mediaMoveFrame = null
    }
    this.pendingMediaMove = null

    this.sortablePointerY = null
    this.mediaDragState = null
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

  async toggleSiteVisibility(event) {
    event.preventDefault()
    event.stopPropagation()

    const button = event.currentTarget
    const tile = this.siteToggleTile(button)
    if (!tile || button.disabled) return

    const previousHidden = tile.dataset.siteHidden === "true"
    const hidden = !previousHidden
    button.disabled = true
    button.setAttribute("aria-busy", "true")
    tile.dataset.siteHidden = hidden ? "true" : "false"
    tile.classList.toggle('is-site-hidden', hidden)

    if (button.dataset.photoId && this.hasHiddenPhotoIdsInputTarget) {
      this.toggleHiddenListValue(this.hiddenPhotoIdsInputTarget, button.dataset.photoId, hidden)
    }

    if (button.dataset.pictureUrl && this.hasHiddenPictureUrlsInputTarget) {
      this.toggleHiddenListValue(this.hiddenPictureUrlsInputTarget, button.dataset.pictureUrl, hidden)
    }

    this.setSiteToggleButton(button, hidden)
    try {
      await this.syncVisibility()
      this.notifySiteVisibility(hidden)
    } catch (_error) {
      tile.dataset.siteHidden = previousHidden ? "true" : "false"
      tile.classList.toggle('is-site-hidden', previousHidden)
      if (button.dataset.photoId && this.hasHiddenPhotoIdsInputTarget) {
        this.toggleHiddenListValue(this.hiddenPhotoIdsInputTarget, button.dataset.photoId, previousHidden)
      }
      if (button.dataset.pictureUrl && this.hasHiddenPictureUrlsInputTarget) {
        this.toggleHiddenListValue(this.hiddenPictureUrlsInputTarget, button.dataset.pictureUrl, previousHidden)
      }
      this.setSiteToggleButton(button, previousHidden)
    } finally {
      button.disabled = false
      button.removeAttribute("aria-busy")
    }
  }

  syncSiteVisibilityControls() {
    this.element.querySelectorAll(".media-photo-site-toggle").forEach((button) => {
      const tile = this.siteToggleTile(button)
      if (!tile) return

      this.setSiteToggleButton(button, tile.dataset.siteHidden === "true")
    })
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
            <img src="${previewUrl}" class="ax-media-tile__image" alt="${this.escapeHtml(file.name)}" draggable="false">
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
    this.refreshMediaDragAndDrop()
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

  // O toggle vive no footer do tile (irmao do frame .media-photo-tile),
  // entao o closest() precisa subir ate o item da grade antes de descer.
  siteToggleTile(button) {
    return button.closest('.media-photo-tile') ||
      button.closest('.ax-media-grid__item')?.querySelector('.media-photo-tile')
  }

  notifySiteVisibility(hidden) {
    const message = hidden ? "Foto despublicada do site." : "Foto publicada no site."
    if (window.axToast) {
      window.axToast({ message, type: hidden ? "info" : "success", timeout: 2400 })
    } else {
      this.showTransientFeedback(message)
    }
  }

  setSiteToggleButton(button, hidden) {
    button.classList.toggle('ax-media-action--published', !hidden)
    button.classList.toggle('ax-media-action--neutral', hidden)
    button.title = hidden ? 'Foto interna, fora do site' : 'Foto publicada no site'
    button.setAttribute('aria-label', button.title)
    button.setAttribute('aria-pressed', hidden ? 'false' : 'true')

    const icon = button.querySelector('i')
    if (icon) {
      icon.classList.toggle('bi-globe2', !hidden)
      icon.classList.toggle('bi-eye-slash', hidden)
    }

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
    if (!this.canSyncVisibility()) {
      throw new Error("Não foi possível localizar a ação de visibilidade desta foto.")
    }

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
      throw error
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
      this.refreshMediaDragAndDrop()
      this.syncSiteVisibilityControls()
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
