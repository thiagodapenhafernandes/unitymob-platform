import { Controller } from "@hotwired/stimulus"

import { readFavorites, writeFavorites, dispatchFavoritesChanged, onFavoritesChanged, offFavoritesChanged } from "controllers/public_favorites_storage"

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
    onFavoritesChanged(this.render)
    this.render()
  }

  disconnect() {
    offFavoritesChanged(this.render)
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

    writeFavorites(favorites)
    dispatchFavoritesChanged()
  }

  render() {
    const active = this.readFavorites().some((favorite) => favorite.id === this.idValue)

    this.element.setAttribute("aria-pressed", String(active))
    this.element.classList.toggle("is-active", active)
    this.iconTarget.classList.toggle("is-active", active)
    this.iconTarget.classList.toggle("bi-heart", !active)
    this.iconTarget.classList.toggle("bi-heart-fill", active)
    const label = active ? "Remover dos favoritos" : "Favoritar imóvel"
    this.labelTarget.textContent = label
    this.element.setAttribute("aria-label", label)
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
    return readFavorites()
  }
}
