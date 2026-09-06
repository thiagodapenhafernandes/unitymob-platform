import { Controller } from "@hotwired/stimulus"

// The user initiated login in the extension. Finish the CSRF-protected handshake;
// this grant cannot read commercial data until terms are accepted in the panel.
export default class extends Controller {
  connect() {
    this.element.requestSubmit()
  }
}
