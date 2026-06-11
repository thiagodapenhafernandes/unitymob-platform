import { Controller } from "@hotwired/stimulus"

const FANCYBOX_SRC = "https://cdn.jsdelivr.net/npm/@fancyapps/ui@5.0/dist/fancybox/fancybox.umd.js"

let fancyboxPromise = null

export default class extends Controller {
  connect() {
    this.open = this.open.bind(this)
    this.element.addEventListener("click", this.open)
    this.ensureFancybox()
  }

  disconnect() {
    this.element.removeEventListener("click", this.open)
  }

  open(event) {
    const trigger = event.target.closest("a[data-fancybox], [data-gallery-open]")
    if (!trigger || !this.element.contains(trigger)) return

    event.preventDefault()
    event.stopPropagation()

    this.ensureFancybox().then(() => {
      const links = this.galleryLinks()
      const startIndex = trigger.hasAttribute("data-gallery-open") ? 0 : Math.max(links.indexOf(trigger), 0)

      window.Fancybox.show(
        links.map((item) => ({
          src: item.href,
          type: "image",
          caption: item.dataset.caption || ""
        })),
        { startIndex }
      )
    })
  }

  galleryLinks() {
    return Array.from(this.element.querySelectorAll("a[data-fancybox]"))
  }

  ensureFancybox() {
    if (window.Fancybox) return Promise.resolve(window.Fancybox)
    if (fancyboxPromise) return fancyboxPromise

    fancyboxPromise = new Promise((resolve, reject) => {
      const existing = document.querySelector(`script[src="${FANCYBOX_SRC}"]`)
      if (existing) {
        existing.addEventListener("load", () => resolve(window.Fancybox), { once: true })
        existing.addEventListener("error", reject, { once: true })
        return
      }

      const script = document.createElement("script")
      script.src = FANCYBOX_SRC
      script.async = true
      script.onload = () => resolve(window.Fancybox)
      script.onerror = reject
      document.head.appendChild(script)
    })

    return fancyboxPromise
  }
}
