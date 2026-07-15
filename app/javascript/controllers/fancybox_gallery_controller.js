import { Controller } from "@hotwired/stimulus"

const DEBUG = false

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
    this.debug("connect", {
      links: this.galleryLinks().length,
      fancyboxAvailable: this.fancyboxAvailable()
    })
    this.ensureFancyboxAssets().catch(() => {})
  }

  disconnect() {
    delete this.element.dataset.fancyboxGalleryReady
    this.element.removeEventListener("click", this.open, true)
    this.debug("disconnect")
  }

  open(event) {
    const trigger = this.triggerFor(event)
    this.debug("click", {
      target: this.describeElement(event.target),
      trigger: this.describeElement(trigger),
      defaultPrevented: event.defaultPrevented
    })

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
        this.debug("open:empty-gallery")
        return
      }

      const startIndex = Math.max(items.findIndex((item) => item.src === galleryTrigger.href), 0)
      this.debug("open:fancybox", { links: items.length, startIndex, href: galleryTrigger.href })
      this.pauseEmbeddableMedia()

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
            destroy: () => this.pauseEmbeddableMedia()
          }
        }
      )
    }).catch((error) => {
      loadingCard?.classList.remove("is-loading")
      console.error("Failed to open image gallery", error)
      this.debug("open:fallback", { error: error.message, href: galleryTrigger.href })
      if (galleryTrigger.matches("a[data-fancybox]") && galleryTrigger.href) window.open(galleryTrigger.href, "_blank", "noopener")
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

    return Boolean(
      target.closest("button, input, select, textarea, label")
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
    if (!this.hasSourceUrlValue) return Promise.resolve(this.galleryLinks().map((item) => this.galleryItem(item)))
    if (this.remoteGalleryItems) return Promise.resolve(this.remoteGalleryItems)
    if (this.galleryRequest) return this.galleryRequest

    this.element.classList.add("is-loading")
    this.galleryRequest = fetch(this.sourceUrlValue, {
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
      this.debug("ensure:available")
      return Promise.resolve(window.Fancybox)
    }
    if (fancyboxPromise) {
      this.debug("ensure:reuse-promise")
      return fancyboxPromise
    }

    this.debug("ensure:import-module")

    // Módulo self-hosted via importmap (vendor/javascript/@fancyapps--ui.js).
    fancyboxPromise = import("@fancyapps/ui").then(({ Fancybox }) => {
      if (!Fancybox || typeof Fancybox.show !== "function") {
        this.debug("ensure:loaded-without-export")
        throw new Error("Fancybox carregou, mas não expôs Fancybox.show.")
      }
      window.Fancybox = window.Fancybox || Fancybox
      this.debug("ensure:loaded")
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

  debug(message, payload = {}) {
    if (!DEBUG) return
    console.log("[fancybox-gallery]", message, payload)
  }

  describeElement(element) {
    if (!element) return null
    const tag = element.tagName ? element.tagName.toLowerCase() : "unknown"
    const id = element.id ? `#${element.id}` : ""
    const classes = element.classList && element.classList.length > 0 ? `.${Array.from(element.classList).join(".")}` : ""
    const fancybox = element.dataset && element.dataset.fancybox ? `[data-fancybox="${element.dataset.fancybox}"]` : ""
    return `${tag}${id}${classes}${fancybox}`
  }
}
