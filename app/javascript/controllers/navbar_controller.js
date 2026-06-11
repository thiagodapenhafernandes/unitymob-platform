import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mobileMenu", "desktopMenu"]

  toggleMobile() {
    this.mobileMenuTarget.classList.toggle("hidden")
  }

  toggleDesktopMenu() {
    this.desktopMenuTarget.classList.toggle("hidden")
  }
}
