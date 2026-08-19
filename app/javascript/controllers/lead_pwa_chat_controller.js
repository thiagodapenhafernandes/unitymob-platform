import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]

  open() {
    if (!this.hasDialogTarget) return

    if (this.dialogTarget.showModal) {
      this.dialogTarget.showModal()
    } else {
      this.dialogTarget.setAttribute("open", "open")
    }
    document.documentElement.classList.add("lead-pwa-chat-lock")
  }

  close() {
    if (!this.hasDialogTarget) return

    if (this.dialogTarget.close) {
      this.dialogTarget.close()
    } else {
      this.dialogTarget.removeAttribute("open")
    }
    document.documentElement.classList.remove("lead-pwa-chat-lock")
  }

  backdropClose(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
