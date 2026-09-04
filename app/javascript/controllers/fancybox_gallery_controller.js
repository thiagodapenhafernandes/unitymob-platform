import { Controller } from "@hotwired/stimulus"

// CSS self-hosted: o layout injeta o link nas telas com galeria e expõe o
// caminho digerido do asset via <meta name="fancybox-css-path"> para carga sob demanda.
function fancyboxStylesheetHref() {
  return document.querySelector('meta[name="fancybox-css-path"]')?.content || null
}

let fancyboxPromise = null
let fancyboxStylesheetPromise = null

export default class extends Controller {
  static values = { sourceUrl: String }

  connect() {
    this.open = this.open.bind(this)
    this.element.dataset.fancyboxGalleryReady = "true"
    this.element.addEventListener("click", this.open, true)
    this.ensureFancyboxAssets().catch(() => {})
  }

  disconnect() {
    delete this.element.dataset.fancyboxGalleryReady
    this.element.removeEventListener("click", this.open, true)
  }

  open(event) {
    const trigger = this.triggerFor(event)

    if (!trigger || !this.element.contains(trigger)) return

    const galleryTrigger = this.galleryAnchorFor(trigger) || trigger

    event.preventDefault()
    event.stopPropagation()
    event.stopImmediatePropagation()

    const loadingCard = galleryTrigger.closest?.(".wa-inbox-media-card")
    if (loadingCard) {
      loadingCard.classList.add("is-loading")
      setTimeout(() => loadingCard.classList.remove("is-loading"), 5000)
    }

    Promise.all([this.ensureFancyboxAssets(), this.galleryItems()]).then(([Fancybox, items]) => {
      if (items.length === 0) {
        return
      }

      const startIndex = Math.max(items.findIndex((item) => item.src === galleryTrigger.href), 0)
      this.pauseEmbeddableMedia()
      const restoreDialog = this.suspendTopLayerDialog(galleryTrigger)

      Fancybox.show(
        items,
        {
          startIndex,
          animated: false,
          dragToClose: false,
          hideScrollbar: false,
          keyboard: {
            Escape: "close",
            Delete: "close",
            Backspace: "close",
            ArrowLeft: "prev",
            ArrowRight: "next"
          },
          closeButton: "top",
          mainClass: "wa-fancybox-shell",
          Toolbar: {
            display: {
              left: [],
              middle: [],
              right: ["close"]
            }
          },
          on: {
            ready: () => loadingCard?.classList.remove("is-loading"),
            close: () => this.pauseEmbeddableMedia(),
            destroy: () => {
              this.pauseEmbeddableMedia()
              restoreDialog()
            }
          }
        }
      )
    }).catch((error) => {
      loadingCard?.classList.remove("is-loading")
      console.error("Failed to open image gallery", error)
      this.galleryItems().then((items) => {
        if (items.length === 0) return

        const startIndex = Math.max(items.findIndex((item) => item.src === galleryTrigger.href), 0)
        this.showFallbackGallery(items, startIndex)
      }).catch(() => {})
    })
  }

  triggerFor(event) {
    const directTrigger = event.target.closest("a[data-fancybox], [data-gallery-open]")
    if (directTrigger && this.element.contains(directTrigger)) {
      if (this.isNestedInteractiveControl(event.target, directTrigger)) return null

      return directTrigger
    }

    if (this.isInteractiveControl(event.target)) return null

    const mediaTile = event.target.closest(".ax-media-tile__frame, .media-photo-tile")
    if (!mediaTile || !this.element.contains(mediaTile)) return null

    return mediaTile.querySelector("a[data-fancybox]")
  }

  isNestedInteractiveControl(target, trigger) {
    if (!target || target === trigger) return false

    const interactiveControl = target.closest("button, input, select, textarea, label")
    if (interactiveControl && interactiveControl === trigger) return false

    return Boolean(
      interactiveControl
    )
  }

  isInteractiveControl(target) {
    return Boolean(
      target.closest(
        [
          "button",
          "input",
          "select",
          "textarea",
          "label",
          "[data-action]",
          ".ax-media-action",
          ".media-photo-drag-handle",
          ".media-photo-action-button",
          ".media-photo-site-toggle",
          ".media-photo-feature-button"
        ].join(",")
      )
    )
  }

  galleryLinks() {
    return Array.from(this.element.querySelectorAll("a[data-fancybox]")).filter((link) => link.href)
  }

  galleryItems() {
    const sourceUrl = this.remoteGallerySourceUrl()

    if (!sourceUrl) return Promise.resolve(this.galleryLinks().map((item) => this.galleryItem(item)))
    if (this.remoteGalleryItems) return Promise.resolve(this.remoteGalleryItems)
    if (this.galleryRequest) return this.galleryRequest

    this.element.classList.add("is-loading")
    this.galleryRequest = fetch(sourceUrl, {
      headers: { Accept: "application/json" },
      credentials: "same-origin"
    }).then((response) => {
      if (!response.ok) throw new Error(`Falha ao carregar galeria (${response.status})`)
      return response.json()
    }).then((payload) => {
      this.remoteGalleryItems = Array.from(payload.items || []).map((item) => ({
        src: item.src,
        type: item.type || "image",
        caption: item.caption || "",
        thumbSrc: item.thumb_src || item.src
      })).filter((item) => item.src)
      return this.remoteGalleryItems
    }).finally(() => {
      this.galleryRequest = null
      this.element.classList.remove("is-loading")
    })

    return this.galleryRequest
  }

  remoteGallerySourceUrl() {
    if (!this.hasSourceUrlValue) return null

    const rawSourceUrl = String(this.sourceUrlValue || "").trim()
    if (!rawSourceUrl) return null

    const sourceUrl = new URL(rawSourceUrl, window.location.href)
    const currentUrl = new URL(window.location.href)

    if (sourceUrl.pathname === currentUrl.pathname && sourceUrl.search === currentUrl.search) return null
    if (!sourceUrl.pathname.endsWith("/gallery")) return null

    return sourceUrl.href
  }

  galleryItem(item) {
    const type = item.dataset.fancyboxType || "image"
    const caption = item.dataset.caption || ""

    if (type === "html") {
      return {
        src: item.dataset.fancyboxHtml || "",
        type,
        caption
      }
    }

    if (type === "inline") {
      const targetMarkup = this.inlineTargetMarkup(item)
      if (targetMarkup) {
        return {
          src: targetMarkup,
          type: "html",
          caption
        }
      }

      return {
        src: item.getAttribute("href"),
        type,
        caption
      }
    }

    if (type === "html5video") {
      return {
        src: item.href,
        type,
        caption,
        html5video: {
          autoplay: true,
          controls: true,
          preload: "metadata"
        }
      }
    }

    if (type === "iframe") {
      return {
        src: item.href,
        type,
        caption,
        preload: false
      }
    }

    return {
      src: item.href,
      type: "image",
      caption,
      thumbSrc: item.dataset.thumbSrc || item.href
    }
  }

  inlineTargetFor(item) {
    const selector = item.getAttribute("href")
    if (!selector || !selector.startsWith("#")) return null
    return document.querySelector(selector)
  }

  inlineTargetMarkup(item) {
    const target = this.inlineTargetFor(item)
    if (!target) return null

    const clone = target.cloneNode(true)
    clone.hidden = false
    clone.removeAttribute("hidden")
    return clone.outerHTML
  }

  galleryAnchorFor(trigger) {
    if (trigger.matches("a[data-fancybox]")) return trigger
    if (trigger.matches("[data-gallery-open]")) return this.galleryLinks()[0]
    return trigger.parentElement?.querySelector("a[data-fancybox]") || trigger.closest('[data-controller~="wa-audio-preview"]')?.querySelector("a[data-fancybox]")
  }

  pauseEmbeddableMedia() {
    document.querySelectorAll("audio, video").forEach((media) => {
      if (typeof media.pause === "function") media.pause()
    })
  }

  showFallbackGallery(items, startIndex = 0) {
    const galleryItems = Array.from(items || []).filter((item) => item.src)
    if (galleryItems.length === 0) return

    let currentIndex = Math.min(Math.max(startIndex, 0), galleryItems.length - 1)
    const overlay = document.createElement("div")
    overlay.className = "ax-fancybox-fallback"
    overlay.setAttribute("role", "dialog")
    overlay.setAttribute("aria-modal", "true")

    const frame = document.createElement("div")
    frame.className = "ax-fancybox-fallback__frame"

    const closeButton = document.createElement("button")
    closeButton.type = "button"
    closeButton.className = "ax-fancybox-fallback__close"
    closeButton.setAttribute("aria-label", "Fechar galeria")
    closeButton.innerHTML = "&times;"

    const image = document.createElement("img")
    image.className = "ax-fancybox-fallback__image"
    image.alt = galleryItems[currentIndex].caption || "Foto do imóvel"

    const counter = document.createElement("div")
    counter.className = "ax-fancybox-fallback__counter"

    const previousButton = document.createElement("button")
    previousButton.type = "button"
    previousButton.className = "ax-fancybox-fallback__nav ax-fancybox-fallback__nav--prev"
    previousButton.setAttribute("aria-label", "Foto anterior")
    previousButton.innerHTML = "&#8249;"

    const nextButton = document.createElement("button")
    nextButton.type = "button"
    nextButton.className = "ax-fancybox-fallback__nav ax-fancybox-fallback__nav--next"
    nextButton.setAttribute("aria-label", "Próxima foto")
    nextButton.innerHTML = "&#8250;"

    const render = () => {
      const item = galleryItems[currentIndex]
      image.src = item.src
      image.alt = item.caption || "Foto do imóvel"
      counter.textContent = `${currentIndex + 1} / ${galleryItems.length}`
      previousButton.hidden = galleryItems.length < 2
      nextButton.hidden = galleryItems.length < 2
    }

    const close = () => {
      document.removeEventListener("keydown", onKeydown)
      overlay.remove()
      document.documentElement.classList.remove("ax-fancybox-fallback-open")
    }
    const showPrevious = () => {
      currentIndex = (currentIndex - 1 + galleryItems.length) % galleryItems.length
      render()
    }
    const showNext = () => {
      currentIndex = (currentIndex + 1) % galleryItems.length
      render()
    }
    const onKeydown = (event) => {
      if (event.key === "Escape") close()
      if (event.key === "ArrowLeft") showPrevious()
      if (event.key === "ArrowRight") showNext()
    }

    closeButton.addEventListener("click", close)
    overlay.addEventListener("click", (event) => {
      if (event.target === overlay) close()
    })
    previousButton.addEventListener("click", showPrevious)
    nextButton.addEventListener("click", showNext)
    document.addEventListener("keydown", onKeydown)

    frame.append(closeButton, image, counter, previousButton, nextButton)
    overlay.appendChild(frame)
    document.body.appendChild(overlay)
    document.documentElement.classList.add("ax-fancybox-fallback-open")
    render()
  }

  suspendTopLayerDialog(trigger) {
    const dialog = trigger.closest("dialog[open]")
    if (!dialog || typeof dialog.close !== "function" || typeof dialog.showModal !== "function") {
      return () => {}
    }

    const body = dialog.querySelector("[class$='preview-modal__body']")
    const scrollTop = body?.scrollTop || 0
    const previewOpenClasses = ["shared-property-preview-open", "field-preview-open"].filter((className) => (
      document.documentElement.classList.contains(className)
    ))
    let restored = false

    dialog.close()

    return () => {
      if (restored || !document.body.contains(dialog) || dialog.open) return

      restored = true
      dialog.showModal()
      previewOpenClasses.forEach((className) => document.documentElement.classList.add(className))
      if (body) body.scrollTop = scrollTop
    }
  }

  ensureFancyboxAssets() {
    return Promise.all([
      this.ensureFancyboxStylesheet(),
      this.ensureFancybox()
    ]).then(([, Fancybox]) => Fancybox)
  }

  ensureFancyboxStylesheet() {
    // Cobre tanto o link renderizado pelo layout (asset local digerido)
    // quanto um link já injetado por esta rotina.
    const existing = document.querySelector('link[rel="stylesheet"][href*="fancybox"]')
    if (existing) {
      if (existing.dataset.fancyboxStylesheetLoaded === "true" || existing.sheet) {
        return Promise.resolve(existing)
      }
    }

    if (fancyboxStylesheetPromise) return fancyboxStylesheetPromise

    fancyboxStylesheetPromise = new Promise((resolve, reject) => {
      const href = fancyboxStylesheetHref()
      if (!existing && !href) {
        reject(new Error("Caminho do CSS do Fancybox indisponível (meta fancybox-css-path ausente)."))
        return
      }

      const stylesheet = existing || document.createElement("link")
      const timeout = window.setTimeout(() => {
        reject(new Error("Tempo limite ao carregar estilos do Fancybox."))
      }, 8000)

      const finish = () => {
        window.clearTimeout(timeout)
        stylesheet.dataset.fancyboxStylesheetLoaded = "true"
        resolve(stylesheet)
      }

      stylesheet.addEventListener("load", finish, { once: true })
      stylesheet.addEventListener("error", (error) => {
        window.clearTimeout(timeout)
        reject(error)
      }, { once: true })

      if (!existing) {
        stylesheet.rel = "stylesheet"
        stylesheet.href = href
        document.head.appendChild(stylesheet)
      }
    }).catch((error) => {
      fancyboxStylesheetPromise = null
      throw error
    })

    return fancyboxStylesheetPromise
  }

  ensureFancybox() {
    if (this.fancyboxAvailable()) {
      return Promise.resolve(window.Fancybox)
    }
    if (fancyboxPromise) {
      return fancyboxPromise
    }

    // Módulo self-hosted via importmap (vendor/javascript/@fancyapps--ui.js).
    fancyboxPromise = import("@fancyapps/ui").then(({ Fancybox }) => {
      if (!Fancybox || typeof Fancybox.show !== "function") {
        throw new Error("Fancybox carregou, mas não expôs Fancybox.show.")
      }
      window.Fancybox = window.Fancybox || Fancybox
      return Fancybox
    }).catch((error) => {
      fancyboxPromise = null
      throw error
    })

    return fancyboxPromise
  }

  fancyboxAvailable() {
    return Boolean(window.Fancybox && typeof window.Fancybox.show === "function")
  }
}
