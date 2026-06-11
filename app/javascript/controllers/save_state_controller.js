import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submitButton", "cancelButton", "spinner", "label", "choice", "modal", "toast", "toastBody"]
  static values = { submittingText: { type: String, default: "Salvando..." } }

  connect() {
    this.submittingNow = false
    this.saveOptionsConfirmed = false
    this.saveOptionsSubmitter = null
    this.defaultLabel = this.hasLabelTarget ? this.labelTarget.textContent : ""
  }

  confirm(event) {
    if (!this.hasSaveOptionsTargets || this.saveOptionsConfirmed || this.skipSaveOptionsFor(event.submitter)) {
      this.saveOptionsConfirmed = false
      return
    }

    event.preventDefault()
    event.stopImmediatePropagation()
    this.saveOptionsSubmitter = event.submitter
    this.showToast("Escolha como deseja concluir o salvamento.")
    this.openModal()
  }

  submitting(event) {
    if (event.defaultPrevented || this.submittingNow) return

    this.submittingNow = true

    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
      this.submitButtonTarget.classList.add("disabled")
    }

    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.classList.add("disabled")
      this.cancelButtonTarget.setAttribute("aria-disabled", "true")
      this.cancelButtonTarget.style.pointerEvents = "none"
    }

    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.remove("d-none")
    }

    if (this.hasLabelTarget) {
      this.labelTarget.textContent = this.submittingTextValue
    }
  }

  submitted(event) {
    const successful = Boolean(event?.detail?.success)

    // Em sucesso com redirect, o Turbo navega e este reset é irrelevante.
    // Em erro de validação, precisamos destravar os botões.
    if (!successful) this.reset()
  }

  reset() {
    this.submittingNow = false

    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = false
      this.submitButtonTarget.classList.remove("disabled")
    }

    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.classList.remove("disabled")
      this.cancelButtonTarget.removeAttribute("aria-disabled")
      this.cancelButtonTarget.style.pointerEvents = ""
    }

    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.add("d-none")
    }

    if (this.hasLabelTarget) {
      this.labelTarget.textContent = this.defaultLabel || "Salvar"
    }
  }

  submitStay(event) {
    event.preventDefault()
    this.submitWithChoice("stay", "Salvando e permanecendo na ficha de cadastro...")
  }

  submitExit(event) {
    event.preventDefault()
    this.submitWithChoice("exit", "Salvando e saindo para o catálogo...")
  }

  cancel(event) {
    event.preventDefault()
    this.hideModal()
    this.showToast("Salvamento cancelado. Nenhuma alteração foi enviada.")
  }

  submitWithChoice(choice, message) {
    this.choiceTarget.value = choice
    this.saveOptionsConfirmed = true
    this.hideModal()
    this.showToast(message)
    window.setTimeout(() => this.requestConfirmedSubmit(), 200)
  }

  skipSaveOptionsFor(submitter) {
    return submitter?.name === "release_to_broker_after_save"
  }

  get hasSaveOptionsTargets() {
    return this.hasChoiceTarget && this.hasModalTarget
  }

  openModal() {
    const bootstrapElement = window.bootstrap || (typeof bootstrap !== "undefined" ? bootstrap : null)

    if (bootstrapElement?.Modal) {
      bootstrapElement.Modal.getOrCreateInstance(this.modalTarget).show()
      return
    }

    this.choiceTarget.value = "exit"
    this.saveOptionsConfirmed = true
    this.requestConfirmedSubmit()
  }

  hideModal() {
    const bootstrapElement = window.bootstrap || (typeof bootstrap !== "undefined" ? bootstrap : null)
    if (!bootstrapElement?.Modal || !this.hasModalTarget) return

    bootstrapElement.Modal.getOrCreateInstance(this.modalTarget).hide()
  }

  showToast(message) {
    if (!this.hasToastTarget || !this.hasToastBodyTarget) return

    this.toastBodyTarget.textContent = message
    const bootstrapElement = window.bootstrap || (typeof bootstrap !== "undefined" ? bootstrap : null)

    if (bootstrapElement?.Toast) {
      bootstrapElement.Toast.getOrCreateInstance(this.toastTarget, { delay: 3500 }).show()
      return
    }

    this.toastTarget.classList.add("show")
    window.setTimeout(() => this.toastTarget.classList.remove("show"), 3500)
  }

  requestConfirmedSubmit() {
    if (this.saveOptionsSubmitter) {
      this.element.requestSubmit(this.saveOptionsSubmitter)
    } else {
      this.element.requestSubmit()
    }
  }
}
