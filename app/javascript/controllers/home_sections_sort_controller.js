import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static values = {
    url: String
  }

  connect() {
    this.sortable = new Sortable(this.element, {
      animation: 150,
      handle: "tr",
      onEnd: this.persistOrder.bind(this)
    })
  }

  disconnect() {
    this.sortable?.destroy()
  }

  persistOrder() {
    if (!this.hasUrlValue) return

    const order = Array.from(this.element.querySelectorAll("tr[data-id]")).map((row) => row.dataset.id)

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({ order })
    }).catch(() => {})
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
