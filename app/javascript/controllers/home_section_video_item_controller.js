import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "source",
    "externalField",
    "uploadField",
    "url",
    "file",
    "media",
    "provider",
    "titleInput",
    "locationInput",
    "priceInput",
    "badgesInput",
    "title",
    "location",
    "price",
    "badges"
  ]

  connect() {
    this.sync()
  }

  sync() {
    const upload = this.sourceTarget.value === "upload"
    this.externalFieldTarget.hidden = upload
    this.uploadFieldTarget.hidden = !upload
    this.element.classList.toggle("is-upload", upload)
    this.renderCopy()
    this.renderMedia(upload)
  }

  renderCopy() {
    // Sem valor ainda, some com o texto em vez de escrever "Prévia do vídeo" por cima da capa real.
    this.fillOrHide(this.titleTarget, this.titleInputTarget.value)
    this.fillOrHide(this.locationTarget, this.locationInputTarget.value)
    this.fillOrHide(this.priceTarget, this.priceInputTarget.value)

    const badges = this.badgesInputTarget.value.split(",").map((badge) => badge.trim()).filter(Boolean).slice(0, 3)
    this.badgesTarget.replaceChildren(...badges.map((badge) => {
      const node = document.createElement("span")
      node.textContent = badge
      return node
    }))
  }

  fillOrHide(target, value) {
    const trimmed = value.trim()
    target.textContent = trimmed
    target.hidden = !trimmed
  }

  renderMedia(upload) {
    const file = this.hasFileTarget ? this.fileTarget.files[0] : null
    if (upload && file) {
      this.mediaTarget.replaceChildren(this.video(URL.createObjectURL(file)))
      this.providerTarget.textContent = file.name
      return
    }

    if (upload) {
      this.placeholder("Arquivo no Spaces")
      return
    }

    const url = this.urlTarget.value.trim()
    const youtube = this.youtubeId(url)
    if (youtube) {
      this.mediaTarget.replaceChildren(this.image(`https://img.youtube.com/vi/${youtube}/hqdefault.jpg`), this.play())
      this.providerTarget.textContent = "YouTube"
      return
    }

    if (this.instagramUrl(url)) {
      // O embed ao vivo do Instagram sempre mostra o próprio cabeçalho/legenda por cima do vídeo
      // (a política de embed do Instagram proíbe ocultar essa atribuição), o que brigava com a
      // nossa legenda sobreposta. Mesmo tratamento do Vimeo abaixo: só rótulo + ícone de play.
      this.placeholder("Instagram")
      return
    }

    if (this.vimeoId(url)) {
      this.placeholder("Vimeo")
      return
    }

    if (this.directVideo(url)) {
      this.mediaTarget.replaceChildren(this.video(url))
      this.providerTarget.textContent = "MP4 direto"
      return
    }

    this.placeholder("Cole uma URL pública do vídeo")
  }

  placeholder(text) {
    this.mediaTarget.replaceChildren(this.play())
    this.providerTarget.textContent = text
  }

  image(src) {
    const img = document.createElement("img")
    img.src = src
    img.alt = ""
    img.loading = "lazy"
    return img
  }

  video(src) {
    const video = document.createElement("video")
    video.src = src
    video.muted = true
    video.playsInline = true
    video.preload = "metadata"
    return video
  }

  play() {
    const icon = document.createElement("i")
    icon.className = "bi bi-play-fill"
    icon.setAttribute("aria-hidden", "true")
    return icon
  }

  youtubeId(raw) {
    if (/^[A-Za-z0-9_-]{11}$/.test(raw)) return raw
    const url = this.url(raw)
    if (!url) return null
    if (url.hostname === "youtu.be") return url.pathname.split("/").filter(Boolean)[0]
    if (!url.hostname.endsWith("youtube.com")) return null
    const parts = url.pathname.split("/").filter(Boolean)
    return ["shorts", "embed"].includes(parts[0]) ? parts[1] : url.searchParams.get("v")
  }

  vimeoId(raw) {
    const url = this.url(raw)
    if (!url || !url.hostname.endsWith("vimeo.com")) return null
    return url.pathname.split("/").reverse().find((part) => /^\d+$/.test(part))
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
}
