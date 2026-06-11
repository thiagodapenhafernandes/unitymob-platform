import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { propertyId: String }

  connect() {
    this.updateIcon()
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    const favorites = this.getFavorites()
    const propertyId = this.propertyIdValue

    if (favorites.includes(propertyId)) {
      // Remove from favorites
      const index = favorites.indexOf(propertyId)
      favorites.splice(index, 1)
    } else {
      // Add to favorites
      favorites.push(propertyId)
    }

    localStorage.setItem('favoritesProperties', JSON.stringify(favorites))
    this.updateIcon()

    // Dispatch event for counter updates
    window.dispatchEvent(new CustomEvent('favorites:changed', {
      detail: { count: favorites.length }
    }))
  }

  getFavorites() {
    const stored = localStorage.getItem('favoriteProperties')
    return stored ? JSON.parse(stored) : []
  }

  isFavorite() {
    return this.getFavorites().includes(this.propertyIdValue)
  }

  updateIcon() {
    const icon = this.element.querySelector('i')
    if (icon) {
      if (this.isFavorite()) {
        icon.classList.remove('bi-bookmark')
        icon.classList.add('bi-bookmark-fill')
        this.element.classList.add('favorited')
      } else {
        icon.classList.remove('bi-bookmark-fill')
        icon.classList.add('bi-bookmark')
        this.element.classList.remove('favorited')
      }
    }
  }
}
