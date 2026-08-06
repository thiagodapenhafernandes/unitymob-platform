import { Controller } from "@hotwired/stimulus"
import {
  clearFavorites,
  dispatchFavoritesChanged,
  offFavoritesChanged,
  onFavoritesChanged,
  readFavorites,
  writeFavorites
} from "controllers/public_favorites_storage"

export default class extends Controller {
  static targets = ["list", "empty", "count", "clear"]

  connect() {
    this.render = this.render.bind(this)
    onFavoritesChanged(this.render)
    this.render()
  }

  disconnect() {
    offFavoritesChanged(this.render)
  }

  clear() {
    clearFavorites()
    dispatchFavoritesChanged()
  }

  render() {
    const favorites = this.readFavorites()
    this.listTarget.replaceChildren(...favorites.map((favorite) => this.cardFor(favorite)))
    this.emptyTarget.hidden = favorites.length > 0
    this.clearTarget.hidden = favorites.length === 0
    this.countTarget.textContent = `${favorites.length} ${favorites.length === 1 ? "imóvel" : "imóveis"}`
  }

  cardFor(favorite) {
    const article = document.createElement("article")
    article.className = "public-favorites__card"

    const link = document.createElement("a")
    link.href = favorite.url
    link.className = "public-favorites__card-image"

    const image = document.createElement("img")
    image.src = favorite.imageUrl
    image.alt = favorite.title
    image.loading = "lazy"
    link.appendChild(image)

    const body = document.createElement("div")
    body.className = "public-favorites__card-body"

    const title = document.createElement("h2")
    title.textContent = favorite.title
    body.appendChild(title)

    if (favorite.price) {
      const price = document.createElement("p")
      price.className = "public-favorites__card-price"
      price.textContent = favorite.price
      body.appendChild(price)
    }

    const location = document.createElement("p")
    location.className = "public-favorites__card-location"
    location.textContent = favorite.location || "Confira os detalhes do imóvel"
    body.appendChild(location)

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "public-favorites__remove"
    remove.innerHTML = '<i class="bi bi-bookmark-heart-fill"></i> Remover'
    remove.addEventListener("click", () => this.remove(favorite.id))
    body.appendChild(remove)

    article.append(link, body)
    return article
  }

  remove(id) {
    const favorites = this.readFavorites().filter((favorite) => favorite.id !== String(id))
    writeFavorites(favorites)
    dispatchFavoritesChanged()
  }

  readFavorites() {
    return readFavorites()
  }
}
