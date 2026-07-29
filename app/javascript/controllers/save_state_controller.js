import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submitButton", "cancelButton", "spinner", "label", "choice", "modal", "toast", "toastBody"]
  static values = { submittingText: { type: String, default: "Salvando..." } }

  connect() {
    this.submittingNow = false
    this.saveOptionsConfirmed = false
    this.saveOptionsSubmitter = null
    this.dirty = false
    this.defaultLabel = this.hasLabelTarget ? this.labelTarget.textContent : ""
    this.toastTimeout = null
    this.boundCloseOnEscape = this.closeOnEscape.bind(this)
    this.boundMarkDirty = this.markDirty.bind(this)
    this.boundBeforeUnload = this.beforeUnload.bind(this)
    this.boundConfirmNavigation = this.confirmNavigation.bind(this)
    this.element.addEventListener("input", this.boundMarkDirty, true)
    this.element.addEventListener("change", this.boundMarkDirty, true)
    window.addEventListener("beforeunload", this.boundBeforeUnload)
    document.addEventListener("click", this.boundConfirmNavigation, true)
  }

  disconnect() {
    this.unlockScroll()
    document.removeEventListener("keydown", this.boundCloseOnEscape)
    document.removeEventListener("click", this.boundConfirmNavigation, true)
    window.removeEventListener("beforeunload", this.boundBeforeUnload)
    this.element.removeEventListener("input", this.boundMarkDirty, true)
    this.element.removeEventListener("change", this.boundMarkDirty, true)
    if (this.toastTimeout) window.clearTimeout(this.toastTimeout)
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
    this.dirty = false

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
      this.spinnerTarget.hidden = false
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
      this.spinnerTarget.hidden = true
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

  closeToast(event) {
    if (event) event.preventDefault()
    this.hideToast()
  }

  backdropCancel(event) {
    if (event.target !== this.modalTarget) return

    event.preventDefault()
    this.hideModal()
  }

  submitWithChoice(choice, message) {
    this.choiceTarget.value = choice
    this.saveOptionsConfirmed = true
    this.hideModal()
    this.showToast(message)
    window.setTimeout(() => this.requestConfirmedSubmit(), 200)
  }

  skipSaveOptionsFor(submitter) {
    return (
      submitter?.name === "release_to_broker_after_save" ||
      submitter?.name === "save_internal_after_save" ||
      submitter?.dataset?.saveStateDirect === "true"
    )
  }

  get hasSaveOptionsTargets() {
    return this.hasChoiceTarget && this.hasModalTarget
  }

  openModal() {
    this.modalTarget.hidden = false
    this.modalTarget.setAttribute("aria-hidden", "false")
    this.modalTarget.classList.add("is-open")
    this.lockScroll()
    document.addEventListener("keydown", this.boundCloseOnEscape)

    const focusable = this.modalTarget.querySelector("[autofocus], button, input, select, textarea, [tabindex]:not([tabindex='-1'])")
    if (focusable) focusable.focus()
  }

  hideModal() {
    if (!this.hasModalTarget) return

    this.modalTarget.classList.remove("is-open")
    this.modalTarget.setAttribute("aria-hidden", "true")
    this.modalTarget.hidden = true
    this.unlockScroll()
    document.removeEventListener("keydown", this.boundCloseOnEscape)
  }

  showToast(message) {
    if (!this.hasToastTarget || !this.hasToastBodyTarget) return

    this.toastBodyTarget.textContent = message
    this.toastTarget.hidden = false
    this.toastTarget.classList.add("is-visible")

    if (this.toastTimeout) window.clearTimeout(this.toastTimeout)
    this.toastTimeout = window.setTimeout(() => this.hideToast(), 3500)
  }

  hideToast() {
    if (!this.hasToastTarget) return

    this.toastTarget.classList.remove("is-visible")
    this.toastTarget.hidden = true
    this.toastTimeout = null
  }

  requestConfirmedSubmit() {
    if (this.saveOptionsSubmitter) {
      this.element.requestSubmit(this.saveOptionsSubmitter)
    } else {
      this.element.requestSubmit()
    }
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.hideModal()
  }

  markDirty(event) {
    if (this.submittingNow || event.target?.dataset?.adminNavigationIgnore === "true") return

    this.dirty = true
  }

  beforeUnload(event) {
    if (!this.dirty || this.submittingNow) return

    event.preventDefault()
    event.returnValue = ""
  }

  confirmNavigation(event) {
    if (!this.dirty || this.submittingNow) return

    const link = event.target.closest?.("a[href]")
    if (!link || link.dataset.adminNavigationIgnore === "true") return
    if (link.target && link.target !== "_self") return
    if (link.href === window.location.href || link.getAttribute("href")?.startsWith("#")) return

    if (window.confirm("Existem alterações não salvas. Deseja sair sem salvar?")) {
      this.dirty = false
      return
    }

    event.preventDefault()
    event.stopImmediatePropagation()
  }

  lockScroll() {
    document.documentElement.style.overflow = "hidden"
  }

  unlockScroll() {
    document.documentElement.style.overflow = ""
  }
}
