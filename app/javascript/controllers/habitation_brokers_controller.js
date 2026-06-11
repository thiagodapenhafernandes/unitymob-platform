import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["template", "container", "modal", "typeSelect", "brokerSelect", "commissionTypeSelect", "commissionValueInput"]

  connect() {
    // We'll use getOrCreateInstance when needed to avoid dependency on global bootstrap at connect time
  }

  showModal(event) {
    // This method is now optional if using data-bs-toggle
    event.preventDefault()
    this.resetModal()
  }

  add(event) {
    event.preventDefault()

    const roleValue = this.typeSelectTarget.value
    const roleLabel = this.typeSelectTarget.options[this.typeSelectTarget.selectedIndex].text
    const brokerId = this.brokerSelectTarget.value
    const brokerName = this.brokerSelectTarget.options[this.brokerSelectTarget.selectedIndex].text
    const commissionTypeValue = this.commissionTypeSelectTarget.value
    const commissionTypeLabel = this.commissionTypeSelectTarget.options[this.commissionTypeSelectTarget.selectedIndex].text
    const commissionValue = this.commissionValueInputTarget.value

    if (!roleValue || !brokerId) {
      alert("Por favor, selecione o tipo e o corretor.")
      return
    }

    const content = this.templateTarget.innerHTML
      .replace(/NEW_RECORD/g, new Date().getTime())
      .replace(/BROKER_NAME/g, brokerName)
      .replace(/ROLE_LABEL/g, roleLabel)
      .replace(/ROLE_VALUE/g, roleValue)
      .replace(/BROKER_ID_VALUE/g, brokerId)
      .replace(/COMMISSION_TYPE_VALUE/g, commissionTypeValue)
      .replace(/COMMISSION_VALUE_DISPLAY/g, `${commissionTypeLabel}: ${commissionValue}`)
      .replace(/COMMISSION_VALUE_VALUE/g, commissionValue)

    this.containerTarget.insertAdjacentHTML('beforeend', content)

    // Hide modal
    const bootstrapElement = window.bootstrap || (typeof bootstrap !== 'undefined' ? bootstrap : null)
    if (bootstrapElement && bootstrapElement.Modal) {
      const modalInstance = bootstrapElement.Modal.getOrCreateInstance(this.modalTarget)
      if (modalInstance) modalInstance.hide()
    } else if (this.modalTarget) {
      // Fallback if bootstrap is not directly accessible - this might happen in some ESM setups
      // but usually the data attributes will handle it if we trigger a close button
      const closeBtn = this.modalTarget.querySelector('[data-bs-dismiss="modal"]')
      if (closeBtn) closeBtn.click()
    }

    this.resetModal()
  }

  remove(event) {
    event.preventDefault()
    const wrapper = event.currentTarget.closest(".nested-fields")
    if (!wrapper) return

    if (wrapper.dataset.newRecord === "true") {
      wrapper.remove()
    } else {
      const destroyInput = wrapper.querySelector("input[name*='_destroy']")
      if (destroyInput) destroyInput.value = "1"
      wrapper.style.display = "none"
    }
  }

  resetModal() {
    this.typeSelectTarget.value = ""
    this.brokerSelectTarget.value = ""
    this.commissionTypeSelectTarget.value = ""
    this.commissionValueInputTarget.value = ""

    // If using TomSelect, we might need to reset it
    if (this.brokerSelectTarget.tomselect) {
      this.brokerSelectTarget.tomselect.clear()
    }
  }
}
