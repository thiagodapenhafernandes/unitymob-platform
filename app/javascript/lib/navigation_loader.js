// Preloader de navegação — fonte única para admin e field.
//
// Contrato:
//   * MOSTRA em qualquer visita real do Turbo (`turbo:visit`: clique, Turbo.visit, voltar/avançar,
//     redirect de form) e em submits de página inteira (`turbo:submit-start`). Não adivinha por
//     clique: link que o JS intercepta, download, frame ou visita cancelada nunca acende o overlay.
//   * ESCONDE só quando o destino está pronto: página trocada (`turbo:load`) + paint + todo
//     controller Stimulus da página conectado + turbo-frames visíveis carregados + imagens da primeira dobra + holds resolvidos.
//   * Estado vive aqui (módulo), não no DOM: o <body> é trocado a cada visita, este módulo não.
//
// API: window.AxNavigation.show(label) / .hide() / .hold(promise) — `hold` adia o fim da navegação
// até a promise resolver (para inicializações assíncronas de uma tela, ex.: gráficos).

const OVERLAY_ID = "adminNavigationPreloader"
const GATE_TIMEOUT_MS = 5000   // teto da espera por controllers/frames depois que a página trocou
const IMAGE_WAIT_MS = 3000     // imagens visíveis: espera curta (foto lenta não deve estender a navegação)
const FAILSAFE_MS = 15000      // teto absoluto desde o início (servidor sem resposta)
const DOWNLOAD_HIDE_MS = 1200  // resposta não-HTML (download): a página não troca, o overlay sai
const CONTENT_TYPE_MISMATCH = -2 // Turbo SystemStatusCode.contentTypeMismatch

export function createNavigationLoader({ document, window }) {
  const html = document.documentElement
  let token = 0
  let active = false
  let visiting = false
  let skipNextVisit = false
  let nextLabel = null
  let failsafeTimer = null
  const holds = new Set()

  const overlay = () => document.getElementById(OVERLAY_ID)
  const frame = () => new Promise((resolve) => window.requestAnimationFrame(resolve))
  const paint = () => frame().then(frame)
  const sleep = (ms) => new Promise((resolve) => window.setTimeout(resolve, ms))

  function setText(title, detail) {
    const el = overlay()
    if (!el) return
    const titleEl = el.querySelector("[data-nav-title]")
    const detailEl = el.querySelector("[data-nav-detail]")
    if (title && titleEl) titleEl.textContent = title
    if (detail && detailEl) detailEl.textContent = detail
  }

  function show(label = "Carregando página...") {
    token += 1
    active = true
    const mine = token
    window.clearTimeout(failsafeTimer)
    failsafeTimer = window.setTimeout(() => hide(mine), FAILSAFE_MS)

    const el = overlay()
    if (el) {
      setText(label, "Preparando workspace administrativo")
      el.hidden = false
      el.classList.remove("has-rendered")
      el.classList.add("is-visible")
    }
    html.classList.add("ax-admin-is-loading")
  }

  // `forToken` impede que um settle/failsafe antigo esconda uma navegação mais nova.
  function hide(forToken = token) {
    if (forToken !== token) return
    active = false
    visiting = false
    window.clearTimeout(failsafeTimer)
    holds.clear()
    const el = overlay()
    if (el) {
      el.classList.remove("is-visible", "has-rendered")
      el.hidden = true
    }
    html.classList.remove("ax-admin-is-loading")
  }

  function hold(promise) {
    if (!active) return promise
    const tracked = Promise.resolve(promise).finally(() => holds.delete(tracked))
    holds.add(tracked)
    return promise
  }

  // ---- Prontidão do destino ----
  let importmapImports
  function knownControllerPaths() {
    if (importmapImports) return importmapImports
    try {
      importmapImports = JSON.parse(document.querySelector('script[type="importmap"]')?.textContent || "{}").imports || {}
    } catch (_e) {
      importmapImports = {}
    }
    return importmapImports
  }

  // Um controller "pendente" existe no importmap (ou já foi registrado) mas ainda não conectou no
  // elemento. Identificadores sem controller (typo, legado) não seguram a navegação.
  function controllersPending() {
    const app = window.Stimulus
    if (!app) return false
    const imports = knownControllerPaths()
    for (const el of document.querySelectorAll("[data-controller]")) {
      for (const id of (el.getAttribute("data-controller") || "").split(/\s+/).filter(Boolean)) {
        if (app.getControllerForElementAndIdentifier(el, id)) continue
        const path = `controllers/${id.replace(/--/g, "/").replace(/-/g, "_")}_controller`
        if (app.router?.modulesByIdentifier?.has(id) || path in imports) return true
      }
    }
    return false
  }

  function inViewport(el) {
    const rect = el.getBoundingClientRect()
    return rect.bottom > 0 && rect.top < (window.innerHeight || 0)
  }

  function framesPending() {
    for (const el of document.querySelectorAll("turbo-frame[src]:not([disabled])")) {
      if (el.dataset.navSettled) continue
      if (el.getAttribute("loading") === "lazy" && !inViewport(el)) continue
      if (el.hasAttribute("busy") || !el.hasAttribute("complete")) return true
    }
    return false
  }

  // Imagens na primeira dobra (cards de imóvel, avatares): sem isso o overlay sai e a foto "pinga" depois.
  function imagesPending() {
    for (const img of document.querySelectorAll("img")) {
      if (!img.complete && inViewport(img)) return true
    }
    return false
  }

  async function ready(mine) {
    const imagesUntil = Date.now() + IMAGE_WAIT_MS
    const pending = () => holds.size || controllersPending() || framesPending() || (Date.now() < imagesUntil && imagesPending())
    while (active && mine === token && pending()) {
      if (holds.size) await Promise.allSettled([...holds])
      else await frame()
    }
  }

  async function settle() {
    if (!active) return
    const mine = token
    await paint()
    if (mine !== token) return
    await Promise.race([ready(mine), sleep(GATE_TIMEOUT_MS)])
    if (mine !== token) return
    await paint()
    hide(mine)
  }

  // ---- Eventos do Turbo ----
  const on = (type, handler, target = document) => target.addEventListener(type, handler)
  const isPreview = () => html.hasAttribute("data-turbo-preview")

  on("turbo:click", (event) => {
    const link = event.target
    nextLabel = link?.dataset?.adminNavigationLabel || null
    if (link?.closest?.("[data-admin-navigation-ignore]")) {
      skipNextVisit = true
      window.setTimeout(() => { skipNextVisit = false }, 0)
    }
  })

  on("turbo:visit", (event) => {
    const label = nextLabel
    nextLabel = null
    if (skipNextVisit) { skipNextVisit = false; return }

    const target = new URL(event.detail?.url || window.location.href, window.location.href)
    const current = window.location
    if (target.hash && target.pathname === current.pathname && target.search === current.search) return

    visiting = true
    show(label || undefined)
  })

  on("turbo:submit-start", (event) => {
    const form = event.target
    if (form.closest?.("[data-admin-navigation-ignore]") || form.dataset?.adminNavigationIgnore === "true") return
    const frameId = form.dataset?.turboFrame ?? form.closest?.("turbo-frame")?.id
    if (frameId && frameId !== "_top") return

    show(form.dataset?.adminNavigationLabel || "Processando...")
  })

  // Resposta sem visita (422 com render, stream): a página vai renderizar/terminar sem `turbo:visit`.
  // Se um redirect virar visita, `visiting` já barra este caminho e o `turbo:load` encerra.
  on("turbo:submit-end", () => { if (active && !visiting) settle() })

  on("turbo:before-render", () => { if (active) setText(null, "Finalizando interface") })
  on("turbo:render", () => {
    if (!active || isPreview()) return
    overlay()?.classList.add("has-rendered")
    if (!visiting) settle() // render sem visita (422 de form): não haverá turbo:load
  })
  on("turbo:load", () => {
    if (isPreview()) return
    visiting = false
    settle()
  })

  // Falhas que não terminam em turbo:load.
  on("turbo:fetch-request-error", (event) => {
    const el = event.target?.closest?.("turbo-frame")
    if (el) el.dataset.navSettled = "1"
    else hide()
  })
  on("turbo:frame-missing", (event) => {
    if (event.target?.dataset) event.target.dataset.navSettled = "1"
  })
  // Resposta não-HTML (download/export): o Turbo faz reload e a página atual permanece.
  on("turbo:reload", (event) => {
    if (event.detail?.reason === "request_failed" && event.detail?.context?.statusCode === CONTENT_TYPE_MISMATCH) {
      const mine = token
      window.setTimeout(() => hide(mine), DOWNLOAD_HIDE_MS)
    }
  })
  on("pageshow", (event) => { if (event.persisted) hide() }, window)

  hide()
  return { show, hide, hold, settle }
}

if (typeof window !== "undefined" && typeof document !== "undefined") {
  window.AxNavigation = createNavigationLoader({ document, window })
}
