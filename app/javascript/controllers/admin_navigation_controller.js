import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay", "title", "detail"]

  // Failsafe: se turbo:load/render nunca chegar (visit cancelado/erro/lento),
  // esconde o overlay sozinho em vez de deixá-lo preso até o reload.
  static FAILSAFE_MS = 10000

  connect() {
    this.showTimer = null
    this.failsafeTimer = null
    this.pendingFrameResumes = []
    this.navigationStartedAt = null
    this.boundClick = this.handleClick.bind(this)
    this.boundSubmit = this.handleSubmit.bind(this)
    this.boundBeforeVisit = this.handleTurboBeforeVisit.bind(this)
    this.boundBeforeRender = this.handleTurboBeforeRender.bind(this)
    this.boundBeforeFrameRender = this.handleTurboBeforeFrameRender.bind(this)
    this.boundRender = this.handleTurboRender.bind(this)
    this.boundLoad = this.handleTurboLoad.bind(this)
    this.boundSubmitEnd = this.handleTurboSubmitEnd.bind(this)
    this.boundBeforeCache = this.handleTurboBeforeCache.bind(this)
    this.boundPageShow = this.handlePageReady.bind(this)
    this.boundNavError = this.hideNow.bind(this)

    document.addEventListener("click", this.boundClick, true)
    document.addEventListener("submit", this.boundSubmit, true)
    document.addEventListener("turbo:before-visit", this.boundBeforeVisit)
    document.addEventListener("turbo:before-render", this.boundBeforeRender)
    document.addEventListener("turbo:before-frame-render", this.boundBeforeFrameRender)
    document.addEventListener("turbo:load", this.boundLoad)
    document.addEventListener("turbo:render", this.boundRender)
    document.addEventListener("turbo:submit-end", this.boundSubmitEnd)
    document.addEventListener("turbo:before-cache", this.boundBeforeCache)
    // Falhas/abortos de navegação que NÃO disparam turbo:load — sem estes, o
    // overlay ficava preso ("Preparando workspace administrativo").
    document.addEventListener("turbo:fetch-request-error", this.boundNavError)
    document.addEventListener("turbo:frame-missing", this.boundNavError)
    window.addEventListener("pageshow", this.boundPageShow)

    // O overlay é turbo-permanent e pode chegar ao novo controller ainda com
    // o estado da página anterior. Ao conectar, o DOM atual já está pronto e
    // qualquer loading herdado deve ser encerrado imediatamente.
    this.handlePageReady()
  }

  disconnect() {
    document.removeEventListener("click", this.boundClick, true)
    document.removeEventListener("submit", this.boundSubmit, true)
    document.removeEventListener("turbo:before-visit", this.boundBeforeVisit)
    document.removeEventListener("turbo:before-render", this.boundBeforeRender)
    document.removeEventListener("turbo:before-frame-render", this.boundBeforeFrameRender)
    document.removeEventListener("turbo:load", this.boundLoad)
    document.removeEventListener("turbo:render", this.boundRender)
    document.removeEventListener("turbo:submit-end", this.boundSubmitEnd)
    document.removeEventListener("turbo:before-cache", this.boundBeforeCache)
    document.removeEventListener("turbo:fetch-request-error", this.boundNavError)
    document.removeEventListener("turbo:frame-missing", this.boundNavError)
    window.removeEventListener("pageshow", this.boundPageShow)
    if (!document.documentElement.classList.contains("ax-admin-is-loading")) {
      this.hideNow()
    }
  }

  handleClick(event) {
    const link = event.target.closest("a[href]")
    if (link && this.isPrimaryMobileNavigationLink(link)) {
      if (this.shouldShowForPrimaryMobileNavigationLink(link, event)) {
        this.show(link.dataset.adminNavigationLabel || "Carregando página...")
      }
      return
    }

    if (!link || !this.shouldShowForLink(link, event)) return

    this.show(link.dataset.adminNavigationLabel || "Carregando página...")
  }

  handleSubmit(event) {
    const form = event.target
    if (!(form instanceof HTMLFormElement) || !this.shouldShowForForm(form)) return

    this.show(form.dataset.adminNavigationLabel || "Processando...")
  }

  handleTurboBeforeVisit(event) {
    const targetUrl = event.detail?.url
    if (!targetUrl || !this.isWorkspaceUrl(targetUrl)) return

    this.show("Carregando página...")
  }

  handleTurboBeforeRender() {
    if (!document.documentElement.classList.contains("ax-admin-is-loading")) return

    if (this.hasDetailTarget) {
      this.detailTarget.textContent = "Finalizando interface"
    }
  }

  handleTurboBeforeFrameRender(event) {
    if (!document.documentElement.classList.contains("ax-admin-is-loading")) return
    if (!event.target?.id?.startsWith("admin_dashboard_")) return

    // Adia o render do frame do dashboard durante a navegação, MAS guarda o
    // resume: sem chamá-lo, o Turbo deixaria o frame preso pra sempre. É
    // retomado no hideNow (fim da navegação / failsafe).
    const resume = event.detail?.resume
    if (typeof resume === "function") {
      event.preventDefault()
      this.pendingFrameResumes.push(resume)
    }
  }

  handleTurboRender() {
    if (this.isTurboPreview()) return

    this.markRendered()
    this.afterNextPaint(() => this.handlePageReady())
  }

  handleTurboLoad() {
    if (this.isTurboPreview()) return

    this.handlePageReady()
  }

  handleTurboSubmitEnd() {
    // Com redirect, erro de validação ou resposta sem nova visita, o submit já
    // terminou e não deve manter o workspace bloqueado esperando turbo:load.
    this.handlePageReady()
  }

  handleTurboBeforeCache() {
    const overlayWasVisible = this.hasOverlayTarget && !this.overlayTarget.hidden
    const htmlWasLoading = document.documentElement.classList.contains("ax-admin-is-loading")

    if (!overlayWasVisible && !htmlWasLoading) return

    const cacheToken = String(performance.now())
    const overlayClasses = overlayWasVisible ? Array.from(this.overlayTarget.classList) : []
    const shownAt = overlayWasVisible ? this.overlayTarget.dataset.shownAt : null

    document.documentElement.dataset.adminNavigationCacheToken = cacheToken
    document.documentElement.classList.remove("ax-admin-is-loading")

    if (overlayWasVisible) {
      this.overlayTarget.hidden = true
      this.overlayTarget.classList.remove("is-visible", "has-rendered")
      delete this.overlayTarget.dataset.shownAt
    }

    // turbo:before-cache roda ainda na página antiga. Limpamos o snapshot, mas
    // restauramos antes do próximo paint para o corretor não ver a página velha
    // sem preloader enquanto o Turbo termina a troca real da tela.
    window.queueMicrotask(() => {
      if (document.documentElement.dataset.adminNavigationCacheToken !== cacheToken) return

      delete document.documentElement.dataset.adminNavigationCacheToken

      if (htmlWasLoading) {
        document.documentElement.classList.add("ax-admin-is-loading")
      }

      if (overlayWasVisible && this.hasOverlayTarget) {
        this.overlayTarget.hidden = false
        this.overlayTarget.className = overlayClasses.join(" ")
        if (shownAt) this.overlayTarget.dataset.shownAt = shownAt
      }
    })
  }

  handlePageReady() {
    this.hideNow()
    this.updateMetrics()
  }

  show(message) {
    window.clearTimeout(this.showTimer)
    this.navigationStartedAt = performance.now()
    this.pageRendered = false
    if (!this.hasOverlayTarget) return

    if (this.hasTitleTarget) this.titleTarget.textContent = message
    if (this.hasDetailTarget) this.detailTarget.textContent = "Preparando workspace administrativo"

    this.overlayTarget.hidden = false
    this.overlayTarget.classList.add("is-visible")
    document.documentElement.classList.add("ax-admin-is-loading")
    // Guardado no elemento (turbo-permanent, sobrevive à troca de instância
    // do controller a cada navegação) e não na instância — é o que permite
    // ao hideNow() do controller da PÁGINA NOVA saber há quanto tempo o
    // overlay está visível desde que foi mostrado pela página ANTERIOR.
    this.overlayTarget.dataset.shownAt = String(performance.now())

    window.clearTimeout(this.failsafeTimer)
    this.failsafeTimer = window.setTimeout(() => this.hideNow(), this.constructor.FAILSAFE_MS)
  }

  hideNow() {
    window.clearTimeout(this.showTimer)
    this.showTimer = null
    this.pageRendered = false
    delete document.documentElement.dataset.adminNavigationCacheToken

    window.clearTimeout(this.failsafeTimer)
    this.failsafeTimer = null

    if (this.hasOverlayTarget) {
      delete this.overlayTarget.dataset.shownAt
      this.overlayTarget.classList.remove("is-visible")
      this.overlayTarget.classList.remove("has-rendered")
      this.overlayTarget.hidden = true
    }

    document.documentElement.classList.remove("ax-admin-is-loading")

    // Libera frames do dashboard que foram adiados durante a navegação.
    if (this.pendingFrameResumes && this.pendingFrameResumes.length) {
      const resumes = this.pendingFrameResumes
      this.pendingFrameResumes = []
      resumes.forEach((resume) => { try { resume() } catch (_e) { /* frame já resolvido */ } })
    }
  }

  markRendered() {
    this.pageRendered = true
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.add("has-rendered")
    }
    if (this.hasDetailTarget) {
      this.detailTarget.textContent = "Finalizando interface"
    }
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

  afterNextPaint(callback) {
    window.requestAnimationFrame(() => window.requestAnimationFrame(callback))
  }

  isTurboPreview() {
    return document.documentElement.hasAttribute("data-turbo-preview")
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

  isPrimaryMobileNavigationLink(link) {
    return Boolean(link.closest(".ax-pwa-bottom-nav"))
  }

  shouldShowForPrimaryMobileNavigationLink(link, event) {
    if (event.defaultPrevented) return false
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return false
    if (link.dataset.turbo === "false") return false
    if (link.target && link.target !== "_self") return false

    const href = link.getAttribute("href")
    if (!href || href === "#") return false

    const url = new URL(href, window.location.href)
    if (url.origin !== window.location.origin) return false
    if (url.pathname === window.location.pathname && url.search === window.location.search && url.hash === window.location.hash) return false

    return true
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

  isWorkspaceUrl(urlValue) {
    const url = new URL(urlValue, window.location.href)
    return url.origin === window.location.origin && (url.pathname.startsWith("/admin") || url.pathname.startsWith("/field"))
  }
}
