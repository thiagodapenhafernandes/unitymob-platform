import { Controller } from "@hotwired/stimulus"

// Modal "Agendar Atividade": alterna os campos visíveis/obrigatórios conforme
// o rádio "Agendar visita" vs "Retornar para o cliente", e revela o campo de
// destinatários quando o convite por e-mail está ligado.
export default class extends Controller {
  static targets = ["visitField", "returnField", "emailRecipients"]

  connect() {
    this.syncActivityKind()
  }

  syncActivityKind() {
    const selected = this.element.querySelector("input[name='activity_kind']:checked")?.value
    const isVisit = selected === "visit"

    this.visitFieldTargets.forEach((field) => this.setFieldActive(field, isVisit))
    this.returnFieldTargets.forEach((field) => this.setFieldActive(field, !isVisit))
  }

  toggleEmailRecipients(event) {
    if (!this.hasEmailRecipientsTarget) return
    this.setFieldActive(this.emailRecipientsTarget, event.target.checked)
  }

  setFieldActive(container, active) {
    container.hidden = !active
    container.querySelectorAll("input, select, textarea").forEach((field) => {
      field.disabled = !active
    })
  }
}
