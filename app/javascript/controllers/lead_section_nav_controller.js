import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  go(event) {
    const hash = event.currentTarget.hash
    if (!hash) return

    const target = document.getElementById(hash.slice(1))
    if (!target) return

    event.preventDefault()
    target.scrollIntoView({ behavior: "smooth", block: "center" })
    target.classList.remove("lead-operational-section--pulse")
    void target.offsetWidth
    target.classList.add("lead-operational-section--pulse")
  }
}
