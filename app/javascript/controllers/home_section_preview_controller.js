import { Controller } from "@hotwired/stimulus"

// Formulário de seção da Home: prévia ao vivo com os dados reais da conta.
export default class extends Controller {
  static targets = ["preview"]
  static values = { previewUrl: String }
  static kindLabels = { properties: "Imóveis", property_videos: "Vídeos", developments: "Empreendimentos", blog: "Blog", cta: "Chamada para contato" }

  connect() {
    this.updateManualState()
    this.refresh()
  }

  disconnect() {
    window.clearTimeout(this.timer)
    this.abort?.abort()
  }

  schedule() {
    this.updateCounts()
    window.clearTimeout(this.timer)
    this.timer = window.setTimeout(() => this.refresh(), 350)
  }

  // Com imóveis escolhidos, os filtros automáticos deixam de valer: a tela avisa e os apaga visualmente.
  updateManualState() {
    const picked = this.element.querySelector("select[name$='[selected_property_ids][]']")?.selectedOptions.length || 0
    const filters = this.element.querySelector("[data-hs-filters]")
    if (!filters) return
    filters.classList.toggle("is-ignored", picked > 0)
    const note = filters.querySelector("[data-hs-filters-note]")
    if (note) note.hidden = picked === 0
  }

  updateCounts() {
    this.updateManualState()
    this.element.querySelectorAll("[data-chip-section]").forEach((section) => {
      const inputs = [...section.querySelectorAll(".ax-toggle-chip__input")]
      const counter = section.querySelector("[data-chip-count]")
      if (counter) counter.textContent = `${inputs.filter((input) => input.checked).length}/${inputs.length}`
    })
  }

  async refresh() {
    const form = this.element.querySelector("form")
    if (!form || !this.hasPreviewTarget) return

    this.abort?.abort()
    this.abort = new AbortController()
    const params = new URLSearchParams()
    for (const [key, value] of new FormData(form)) {
      if (key !== "_method" && key !== "authenticity_token" && typeof value === "string") params.append(key, value)
    }
    this.slot("state").textContent = "Atualizando…"

    try {
      const response = await fetch(`${this.previewUrlValue}?${params}`, { headers: { Accept: "application/json" }, signal: this.abort.signal, credentials: "same-origin" })
      if (!response.ok) throw new Error(response.status)
      this.render(await response.json())
    } catch (error) {
      if (error.name !== "AbortError") this.slot("state").textContent = "Prévia indisponível"
    }
  }

  slot(name) { return this.previewTarget.querySelector(`[data-pv='${name}']`) }

  render(data) {
    data = this.withManualVideoPreviews(data)
    const state = this.slot("state")
    state.textContent = data.active ? "Visível na Home" : "Oculta da Home"
    state.dataset.state = data.active ? "on" : "off"
    this.slot("kind").textContent = this.constructor.kindLabels[data.kind] || "Seção"

    const title = this.slot("title")
    title.textContent = data.title || "Título da seção"
    title.classList.toggle("is-placeholder", !data.title)
    const subtitle = this.slot("subtitle")
    subtitle.textContent = data.subtitle
    subtitle.hidden = !data.subtitle

    this.slot("body").replaceChildren(...this.bodyFor(data))

    const cta = this.slot("cta")
    cta.textContent = data.cta_label || ""
    cta.hidden = !data.cta_label

    const note = this.slot("note")
    const notes = []
    if (data.warning) notes.push(data.warning)
    else if (data.manual > 0) {
      notes.push(`Só os ${data.manual} imóvel(is) escolhido(s) aparecem; os filtros são ignorados.`)
    } else if (data.kind === "properties" || data.kind === "property_videos" || data.kind === "developments") {
      notes.push(`${data.count} de até ${data.limit} vagas na Home` + (data.matching > data.count ? ` · ${data.matching} atendem aos filtros` : ""))
    }
    if (data.corporate != null) notes.push(`Vitrine corporate: ${data.corporate} imóvel(is)`)
    note.textContent = notes.join(" — ")
    note.hidden = notes.length === 0
    note.dataset.tone = data.warning ? "warning" : "info"
  }

  bodyFor(data) {
    if (data.kind === "cta") return [this.row(data.buttons.map((label) => this.el("span", "hs-pv__btn", label)))]
    if (data.kind === "blog") return data.items.map((item) => this.row([this.el("strong", "", item.title), this.el("small", "", item.meta || "")]))
    const cards = data.items.slice(0, 3).map((item) => {
      const card = this.el("article", data.kind === "property_videos" ? "hs-pv__card hs-pv__card--video" : "hs-pv__card")
      const photo = this.el("div", "hs-pv__photo")
      if (item.embed_url) {
        const frame = document.createElement("iframe")
        frame.src = item.embed_url
        frame.title = "Prévia do vídeo"
        frame.loading = "lazy"
        frame.allow = "autoplay; encrypted-media; picture-in-picture"
        photo.append(frame)
      } else if (item.direct_url) {
        const video = document.createElement("video")
        video.src = item.direct_url
        video.muted = true
        video.playsInline = true
        video.preload = "metadata"
        photo.append(video)
      } else if (item.photo) {
        const img = document.createElement("img")
        img.src = item.photo
        img.alt = ""
        img.loading = "lazy"
        photo.append(img)
      }
      if (data.kind === "property_videos") {
        photo.append(this.el("i", "bi bi-play-fill hs-pv__play"))
        const badges = this.el("div", "hs-pv__badges", null, (item.badges || []).map((badge) => this.el("span", "", badge)))
        card.append(photo, badges)
      } else {
        card.append(photo)
      }
      card.append(this.el("strong", "", item.price), this.el("span", "", item.title), this.el("small", "", item.location))
      return card
    })
    return cards.length ? [this.el("div", "hs-pv__grid", null, cards)] : []
  }

  withManualVideoPreviews(data) {
    if (data.kind !== "property_videos") return data

    const manual = [...this.element.querySelectorAll(".hs-video-item")]
      .filter((item) => item.offsetParent !== null && item.querySelector("input[name*='_destroy']")?.value !== "1")
      .filter((item) => item.querySelector("input[type='checkbox'][name*='[active]']")?.checked !== false)
      .map((item) => this.manualVideoItem(item))
      .filter(Boolean)

    if (manual.length === 0) return data
    return { ...data, items: [...manual, ...(data.items || [])].slice(0, 3), count: Math.max(data.count || 0, manual.length) }
  }

  manualVideoItem(item) {
    const source = item.querySelector("select[name*='[source_type]']")?.value || "external"
    const title = item.querySelector("input[name*='[title]']")?.value.trim()
    const price = item.querySelector("input[name*='[price_label]']")?.value.trim()
    const location = item.querySelector("input[name*='[location]']")?.value.trim()
    const badges = (item.querySelector("input[name*='[badges_text]']")?.value || "").split(",").map((badge) => badge.trim()).filter(Boolean).slice(0, 2)
    const file = item.querySelector("input[type='file']")?.files[0]
    const url = item.querySelector("input[name*='[source_url]']")?.value.trim()
    const media = source === "upload" && file ? { direct_url: URL.createObjectURL(file) } : this.videoPreviewFor(url)

    // Mesmo corte do backend (HomeSections::Preview#manual_video_items): sem título o item nunca
    // aparece na Home de verdade, então a prévia não deve fingir um card fantasma pra ele.
    if (!title) return null
    return { title, price: price || "Valor", location: location || "Localidade", badges, ...(media || {}) }
  }

  videoPreviewFor(raw) {
    const youtube = this.youtubeId(raw)
    if (youtube) return { photo: `https://img.youtube.com/vi/${youtube}/hqdefault.jpg` }
    const instagram = this.instagramUrl(raw)
    if (instagram) return { embed_url: instagram }
    if (this.directVideo(raw)) return { direct_url: raw }
    return null
  }

  youtubeId(raw) {
    if (/^[A-Za-z0-9_-]{11}$/.test(raw || "")) return raw
    const url = this.url(raw)
    if (!url) return null
    if (url.hostname === "youtu.be") return url.pathname.split("/").filter(Boolean)[0]
    if (!url.hostname.endsWith("youtube.com")) return null
    const parts = url.pathname.split("/").filter(Boolean)
    return ["shorts", "embed"].includes(parts[0]) ? parts[1] : url.searchParams.get("v")
  }

  instagramUrl(raw) {
    const url = this.url(raw)
    if (!url || !url.hostname.endsWith("instagram.com")) return null
    const [type, code] = url.pathname.split("/").filter(Boolean)
    if (!["p", "reel", "tv"].includes(type) || !code) return null
    return `https://www.instagram.com/${type}/${code}/embed`
  }

  directVideo(raw) {
    const url = this.url(raw)
    return url && /\.(mp4|mov|m4v|webm|ogg|ogv|3gp)$/i.test(url.pathname)
  }

  url(raw) {
    try {
      return new URL(raw)
    } catch {
      return null
    }
  }

  row(children) { return this.el("div", "hs-pv__row", null, children) }

  el(tag, className, text, children = []) {
    const node = document.createElement(tag)
    if (className) node.className = className
    if (text) node.textContent = text
    node.append(...children)
    return node
  }
}
