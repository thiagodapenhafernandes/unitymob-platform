import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { title: String }

  play(event) {
    event.preventDefault()
    const frame = document.createElement("iframe")
    frame.src = this.element.href
    frame.title = this.titleValue
    frame.allow = "encrypted-media; picture-in-picture; fullscreen"
    frame.allowFullscreen = true
    frame.referrerPolicy = "strict-origin-when-cross-origin"
    this.element.replaceWith(frame)
    frame.focus()
  }
}
