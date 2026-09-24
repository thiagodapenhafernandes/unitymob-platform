import { Controller } from "@hotwired/stimulus"

const FAVORITES_KEY = "public:favorite-properties"
const FAVORITES_CHANGED_EVENT = "public:favorites-changed"

export default class extends Controller {
  static targets = ["icon", "label"]
  static values = {
    id: String,
    url: String,
    title: String,
    imageUrl: String,
    price: String,
    location: String
  }

  connect() {
    this.render = this.render.bind(this)
    window.addEventListener(FAVORITES_CHANGED_EVENT, this.render)
    this.render()
  }

  disconnect() {
    window.removeEventListener(FAVORITES_CHANGED_EVENT, this.render)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    const favorites = this.readFavorites()
    const index = favorites.findIndex((favorite) => favorite.id === this.idValue)

    if (index >= 0) {
      favorites.splice(index, 1)
    } else {
      favorites.unshift(this.propertyData())
    }

    window.localStorage.setItem(FAVORITES_KEY, JSON.stringify(favorites))
    window.dispatchEvent(new CustomEvent(FAVORITES_CHANGED_EVENT))
  }

  render() {
    const active = this.readFavorites().some((favorite) => favorite.id === this.idValue)

    this.element.setAttribute("aria-pressed", String(active))
    this.element.classList.toggle("is-active", active)
    this.iconTarget.classList.toggle("is-active", active)
    this.iconTarget.classList.toggle("bi-heart", !active)
    this.iconTarget.classList.toggle("bi-heart-fill", active)
    this.labelTarget.textContent = active ? "Remover dos favoritos" : "Favoritar imóvel"
  }

  propertyData() {
    return {
      id: this.idValue,
      url: this.urlValue,
      title: this.titleValue,
      imageUrl: this.imageUrlValue,
      price: this.priceValue,
      location: this.locationValue
    }
  }

  readFavorites() {
    try {
      const favorites = JSON.parse(window.localStorage.getItem(FAVORITES_KEY) || "[]")
      return Array.isArray(favorites) ? favorites : []
    } catch (_error) {
      return []
    }
  }
}
