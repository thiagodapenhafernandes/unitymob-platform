import { Controller } from "@hotwired/stimulus"

const FANCYBOX_SRC = "https://cdn.jsdelivr.net/npm/@fancyapps/ui@5.0/dist/fancybox/fancybox.umd.js"
const FANCYBOX_CSS_SRC = "https://cdn.jsdelivr.net/npm/@fancyapps/ui@5.0/dist/fancybox/fancybox.css"
const DEBUG = false

let fancyboxPromise = null
let fancyboxStylesheetPromise = null

export default class extends Controller {
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

    this.ensureFancyboxAssets().then((Fancybox) => {
      const links = this.galleryLinks()
      if (links.length === 0) {
        this.debug("open:empty-gallery")
        return
      }

      const startIndex = Math.max(links.indexOf(galleryTrigger), 0)
      this.debug("open:fancybox", { links: links.length, startIndex, href: galleryTrigger.href })
      this.pauseEmbeddableMedia()

      Fancybox.show(
        links.map((item) => this.galleryItem(item)),
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
            close: () => this.pauseEmbeddableMedia(),
            destroy: () => this.pauseEmbeddableMedia()
          }
        }
      )
    }).catch((error) => {
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
      caption
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
    const existing = document.querySelector(`link[href="${FANCYBOX_CSS_SRC}"]`)
    if (existing) {
      if (existing.dataset.fancyboxStylesheetLoaded === "true" || existing.sheet) {
        return Promise.resolve(existing)
      }
    }

    if (fancyboxStylesheetPromise) return fancyboxStylesheetPromise

    fancyboxStylesheetPromise = new Promise((resolve, reject) => {
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
        stylesheet.href = FANCYBOX_CSS_SRC
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

    this.debug("ensure:load-script")

    fancyboxPromise = new Promise((resolve, reject) => {
      const timeout = window.setTimeout(() => {
        reject(new Error("Tempo limite ao carregar Fancybox."))
      }, 8000)

      const finish = () => {
        window.clearTimeout(timeout)
        if (this.fancyboxAvailable()) {
          this.debug("ensure:loaded")
          resolve(window.Fancybox)
        } else {
          this.debug("ensure:loaded-without-global")
          reject(new Error("Fancybox carregou, mas não inicializou window.Fancybox."))
        }
      }

      const existing = document.querySelector(`script[src="${FANCYBOX_SRC}"]`)
      if (existing) {
        this.debug("ensure:existing-script", {
          loaded: existing.dataset.fancyboxLoaded,
          readyState: existing.readyState
        })
        if (existing.dataset.fancyboxLoaded === "true" || existing.readyState === "complete" || existing.readyState === "loaded") {
          window.queueMicrotask(finish)
          return
        }

        existing.addEventListener("load", finish, { once: true })
        existing.addEventListener("error", (error) => {
          window.clearTimeout(timeout)
          reject(error)
        }, { once: true })
        return
      }

      const script = document.createElement("script")
      script.src = FANCYBOX_SRC
      script.async = true
      script.onload = () => {
        script.dataset.fancyboxLoaded = "true"
        finish()
      }
      script.onerror = (error) => {
        window.clearTimeout(timeout)
        reject(error)
      }
      document.head.appendChild(script)
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
