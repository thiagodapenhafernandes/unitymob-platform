import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Reordena as linhas do menu por arrasto. A ordem vai para o hidden
// data-role="position" via o updatePositions do nested-form, que já é quem
// o normalize do PublicHeaderMenu lê no submit.
export default class extends Controller {
  connect() {
    this.sortable = new Sortable(this.element, {
      handle: ".hm-row__handle",
      animation: 150,
      ghostClass: "hm-row--ghost",
      onEnd: () => {
        this.application
          .getControllerForElementAndIdentifier(
            this.element.closest("[data-controller*='nested-form']"),
            "nested-form"
          )
          ?.updatePositions()
        this.element.dispatchEvent(new Event("change", { bubbles: true }))
      }
    })
  }

  disconnect() {
    this.sortable?.destroy()
  }
}
