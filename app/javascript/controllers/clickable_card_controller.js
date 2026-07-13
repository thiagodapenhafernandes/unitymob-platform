import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.isDragging = false
    this.dragStartTime = null
    this.boundMouseDown = this.handleMouseDown.bind(this)
    this.boundTouchStart = this.handleTouchStart.bind(this)
    this.boundMouseUp = this.handleMouseUp.bind(this)
    this.boundTouchEnd = this.handleTouchEnd.bind(this)
    this.boundMouseMove = this.handleMouseMove.bind(this)
    this.boundTouchMove = this.handleTouchMove.bind(this)
    this.boundClick = this.handleClick.bind(this)

    // Detecta início de drag/swipe
    this.element.addEventListener('mousedown', this.boundMouseDown)
    this.element.addEventListener('touchstart', this.boundTouchStart)

    // Detecta fim de drag
    this.element.addEventListener('mouseup', this.boundMouseUp)
    this.element.addEventListener('touchend', this.boundTouchEnd)

    // Detecta movimento (indica drag)
    this.element.addEventListener('mousemove', this.boundMouseMove)
    this.element.addEventListener('touchmove', this.boundTouchMove)

    // Adiciona evento de clique no card
    this.element.addEventListener('click', this.boundClick)
  }

  disconnect() {
    this.element.removeEventListener('mousedown', this.boundMouseDown)
    this.element.removeEventListener('touchstart', this.boundTouchStart)
    this.element.removeEventListener('mouseup', this.boundMouseUp)
    this.element.removeEventListener('touchend', this.boundTouchEnd)
    this.element.removeEventListener('mousemove', this.boundMouseMove)
    this.element.removeEventListener('touchmove', this.boundTouchMove)
    this.element.removeEventListener('click', this.boundClick)
  }

  handleMouseDown(event) {
    this.isDragging = false
    this.dragStartTime = Date.now()
    this.startX = event.clientX
    this.startY = event.clientY
  }

  handleTouchStart(event) {
    this.isDragging = false
    this.dragStartTime = Date.now()
    const touch = event.touches[0]
    this.startX = touch.clientX
    this.startY = touch.clientY
  }

  handleMouseMove(event) {
    if (this.dragStartTime) {
      const deltaX = Math.abs(event.clientX - this.startX)
      const deltaY = Math.abs(event.clientY - this.startY)

      // Se moveu mais de 5px, considera como drag
      if (deltaX > 5 || deltaY > 5) {
        this.isDragging = true
      }
    }
  }

  handleTouchMove(event) {
    if (this.dragStartTime) {
      const touch = event.touches[0]
      const deltaX = Math.abs(touch.clientX - this.startX)
      const deltaY = Math.abs(touch.clientY - this.startY)

      // Se moveu mais de 5px, considera como drag
      if (deltaX > 5 || deltaY > 5) {
        this.isDragging = true
      }
    }
  }

  handleMouseUp() {
    this.dragStartTime = null
  }

  handleTouchEnd() {
    this.dragStartTime = null
  }

  handleClick(event) {
    // Se foi um drag/swipe, não navega
    if (this.isDragging) {
      this.isDragging = false
      return
    }

    // Não intercepta elementos interativos internos
    const target = event.target
    if (target.closest('a, button, input, select, textarea, label, .dropdown, .dropdown-menu, [data-action]')) {
      return
    }

    // Se clicou em botões do Swiper, não navega
    if (target.closest('.swiper-button-next') ||
      target.closest('.swiper-button-prev') ||
      target.closest('.swiper-pagination')) {
      return
    }

    // Navega para a página do imóvel
    if (this.urlValue) {
      const trackingLink = this.element.querySelector('[data-clickable-card-tracking-link]')

      if (trackingLink) {
        trackingLink.click()
      } else {
        Turbo.visit(this.urlValue)
      }
    }
  }
}
