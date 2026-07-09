import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "status"]
  static values = {
    generateUrl: String,
    fallbackUrl: String,
    propertyTitle: String
  }

  connect() {
    this.sharedUrl = this.fallbackUrlValue
    this.onOutsideClick = this.handleOutsideClick.bind(this)
    if (this.hasMenuTarget) {
      document.addEventListener("click", this.onOutsideClick)
    }
  }

  disconnect() {
    document.removeEventListener("click", this.onOutsideClick)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.hasMenuTarget) return

    if (this.menuVisible()) {
      this.hideMenu()
    } else {
      this.showMenu()
    }
  }

  async shareNative(event) {
    event.preventDefault()
    event.stopPropagation()
    const url = await this.ensureSharedUrl()

    if (navigator.share) {
      try {
        await navigator.share({
          title: this.propertyTitleValue || document.title,
          text: this.propertyTitleValue || "Confira este imóvel",
          url
        })
        this.flashStatus("Compartilhado")
        return
      } catch (error) {
        // user canceled native share; continue silently
      }
    }

    await this.copyFromUrl(url)
  }

  async copy(event) {
    event.preventDefault()
    event.stopPropagation()
    const url = await this.ensureSharedUrl()
    await this.copyFromUrl(url)
  }

  async whatsapp(event) {
    event.preventDefault()
    event.stopPropagation()
    const url = await this.ensureSharedUrl()
    const text = encodeURIComponent(`${this.propertyTitleValue || "Confira este imóvel"} ${url}`)
    window.open(`https://wa.me/?text=${text}`, "_blank")
  }

  async email(event) {
    event.preventDefault()
    event.stopPropagation()
    const url = await this.ensureSharedUrl()
    const subject = encodeURIComponent(this.propertyTitleValue || "Imóvel")
    const body = encodeURIComponent(`Confira este imóvel: ${url}`)
    window.location.href = `mailto:?subject=${subject}&body=${body}`
  }

  async facebook(event) {
    event.preventDefault()
    event.stopPropagation()
    const url = encodeURIComponent(await this.ensureSharedUrl())
    window.open(`https://www.facebook.com/sharer/sharer.php?u=${url}`, "facebook-share-dialog", "width=626,height=436")
  }

  async twitter(event) {
    event.preventDefault()
    event.stopPropagation()
    const rawUrl = await this.ensureSharedUrl()
    const url = encodeURIComponent(rawUrl)
    const text = encodeURIComponent(this.propertyTitleValue || document.title)
    window.open(`https://twitter.com/intent/tweet?url=${url}&text=${text}`, "twitter-share-dialog", "width=626,height=436")
  }

  async ensureSharedUrl() {
    if (!this.generateUrlValue) return this.fallbackUrlValue || window.location.href
    if (this.sharedUrl && this.sharedUrl.includes("share_token=")) return this.sharedUrl

    const csrfToken = document.querySelector("[name='csrf-token']")?.content
    const response = await fetch(this.generateUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Accept": "application/json"
      }
    })

    if (!response.ok) {
      this.flashStatus("Erro ao gerar link")
      return this.fallbackUrlValue || window.location.href
    }

    const payload = await response.json()
    if (payload?.url) this.sharedUrl = payload.url

    return this.sharedUrl || this.fallbackUrlValue || window.location.href
  }

  async copyFromUrl(url) {
    try {
      await navigator.clipboard.writeText(url)
      this.flashStatus("Link copiado")
    } catch (_error) {
      this.flashStatus("Copie manualmente")
    }
  }

  flashStatus(message) {
    if (window.axToast) window.axToast({ message, type: message.toLowerCase().includes("erro") ? "danger" : "success", timeout: 2400 })
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message
    this.showElement(this.statusTarget)
    clearTimeout(this._statusTimer)
    this._statusTimer = setTimeout(() => {
      this.hideElement(this.statusTarget)
    }, 1600)
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target) && this.hasMenuTarget) {
      this.hideMenu()
    }
  }

  menuVisible() {
    if (!this.hasMenuTarget) return false
    return !this.menuTarget.hidden && !this.menuTarget.classList.contains("hidden") && !this.menuTarget.classList.contains("tw-hidden")
  }

  showMenu() {
    if (!this.hasMenuTarget) return
    this.showElement(this.menuTarget)
  }

  hideMenu() {
    if (!this.hasMenuTarget) return
    this.hideElement(this.menuTarget)
  }

  showElement(element) {
    element.hidden = false
    element.classList.remove("hidden", "tw-hidden", "d-none")
  }

  hideElement(element) {
    element.hidden = true
    element.classList.add("hidden", "tw-hidden")
  }
}
