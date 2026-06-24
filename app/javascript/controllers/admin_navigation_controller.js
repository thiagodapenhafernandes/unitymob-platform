import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay", "title", "detail"]

  connect() {
    this.showTimer = null
    this.navigationStartedAt = null
    this.boundClick = this.handleClick.bind(this)
    this.boundSubmit = this.handleSubmit.bind(this)
    this.boundBeforeVisit = this.handleTurboBeforeVisit.bind(this)
    this.boundBeforeFrameRender = this.handleTurboBeforeFrameRender.bind(this)
    this.boundLoad = this.handlePageReady.bind(this)
    this.boundBeforeCache = this.hideNow.bind(this)
    this.boundPageShow = this.handlePageReady.bind(this)

    document.addEventListener("click", this.boundClick, true)
    document.addEventListener("submit", this.boundSubmit, true)
    document.addEventListener("turbo:before-visit", this.boundBeforeVisit)
    document.addEventListener("turbo:before-frame-render", this.boundBeforeFrameRender)
    document.addEventListener("turbo:load", this.boundLoad)
    document.addEventListener("turbo:render", this.boundLoad)
    document.addEventListener("turbo:before-cache", this.boundBeforeCache)
    window.addEventListener("pageshow", this.boundPageShow)

    this.handlePageReady()
  }

  disconnect() {
    document.removeEventListener("click", this.boundClick, true)
    document.removeEventListener("submit", this.boundSubmit, true)
    document.removeEventListener("turbo:before-visit", this.boundBeforeVisit)
    document.removeEventListener("turbo:before-frame-render", this.boundBeforeFrameRender)
    document.removeEventListener("turbo:load", this.boundLoad)
    document.removeEventListener("turbo:render", this.boundLoad)
    document.removeEventListener("turbo:before-cache", this.boundBeforeCache)
    window.removeEventListener("pageshow", this.boundPageShow)
    this.hideNow()
  }

  handleClick(event) {
    const link = event.target.closest("a[href]")
    if (!link || !this.shouldShowForLink(link, event)) return

    this.showSoon(link.dataset.adminNavigationLabel || "Carregando página...")
  }

  handleSubmit(event) {
    const form = event.target
    if (!(form instanceof HTMLFormElement) || !this.shouldShowForForm(form)) return

    this.showSoon(form.dataset.adminNavigationLabel || "Processando...")
  }

  handleTurboBeforeVisit(event) {
    const targetUrl = event.detail?.url
    if (!targetUrl || !this.isAdminUrl(targetUrl)) return

    this.showSoon("Carregando página...")
  }

  handleTurboBeforeFrameRender(event) {
    if (!document.documentElement.classList.contains("ax-admin-is-loading")) return
    if (!event.target?.id?.startsWith("admin_dashboard_")) return

    event.preventDefault()
  }

  handlePageReady() {
    this.hideNow()
    this.updateMetrics()
  }

  showSoon(message) {
    window.clearTimeout(this.showTimer)
    this.navigationStartedAt = performance.now()
    this.show(message)
  }

  show(message) {
    if (!this.hasOverlayTarget) return

    if (this.hasTitleTarget) this.titleTarget.textContent = message
    if (this.hasDetailTarget) this.detailTarget.textContent = "Preparando workspace administrativo"

    this.overlayTarget.hidden = false
    this.overlayTarget.classList.add("is-visible")
    document.documentElement.classList.add("ax-admin-is-loading")
  }

  hideNow() {
    window.clearTimeout(this.showTimer)
    this.showTimer = null

    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.remove("is-visible")
      this.overlayTarget.hidden = true
    }

    document.documentElement.classList.remove("ax-admin-is-loading")
  }

  updateMetrics() {
    const serverMs = this.element.dataset.adminRenderMs
    const page = this.element.dataset.adminRenderPage
    const clientMs = this.clientNavigationDuration()

    if (serverMs || clientMs) {
      window.dispatchEvent(new CustomEvent("admin:navigation-metrics", {
        detail: {
          page,
          serverMs: Number(serverMs || 0),
          clientMs: Number(clientMs || 0)
        }
      }))
    }
  }

  clientNavigationDuration() {
    const navigation = performance.getEntriesByType?.("navigation")?.[0]
    if (navigation?.duration) return navigation.duration
    if (this.navigationStartedAt) return performance.now() - this.navigationStartedAt

    return null
  }

  shouldShowForLink(link, event) {
    if (event.defaultPrevented) return false
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return false
    if (link.closest("[data-admin-navigation-ignore]")) return false
    if (link.dataset.turbo === "false") return false
    if (link.dataset.bsToggle || link.getAttribute("data-bs-toggle")) return false
    if (this.isUiOnlyLink(link)) return false
    if (link.hasAttribute("download")) return false
    if (link.target && link.target !== "_self") return false
    if (link.dataset.turboMethod || link.dataset.method || link.getAttribute("rel")?.includes("nofollow")) return false

    const href = link.getAttribute("href")
    if (!href || href === "#") return false

    const url = new URL(href, window.location.href)
    if (url.origin !== window.location.origin) return false
    if (url.pathname === window.location.pathname && url.search === window.location.search && url.hash) return false

    return this.isAdminUrl(url.href)
  }

  isUiOnlyLink(link) {
    const action = link.dataset.action || ""
    const uiOnlyAction = /#(toggle|open|close|backdropClose|dismiss|select|remove|add)\b/.test(action)

    return Boolean(
      uiOnlyAction ||
      link.dataset.mediaModalUrl ||
      link.hasAttribute("data-gallery-open") ||
      link.hasAttribute("data-fancybox")
    )
  }

  shouldShowForForm(form) {
    if (form.closest("[data-admin-navigation-ignore]")) return false
    if (form.dataset.adminNavigationIgnore === "true") return false
    if (form.dataset.photoUploadAsyncSubmit === "true") return false
    if (form.dataset.remote === "true") return false
    if (form.dataset.internalDocumentUploadForm) return false
    if (form.target && form.target !== "_self") return false

    const action = form.getAttribute("action") || window.location.href
    return this.isAdminUrl(action)
  }

  isAdminUrl(urlValue) {
    const url = new URL(urlValue, window.location.href)
    return url.origin === window.location.origin && url.pathname.startsWith("/admin")
  }
}
