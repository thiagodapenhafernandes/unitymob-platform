import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["template", "container", "modal", "typeSelect", "brokerSelect", "commissionTypeSelect", "commissionValueInput"]

  showModal(event) {
    event.preventDefault()
    this.resetModal()
    this.modalTarget.dispatchEvent(new CustomEvent("ax-modal:open", { bubbles: true }))
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
      window.axToast({ message: "Por favor, selecione o tipo e o corretor.", type: "warning" })
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

    this.modalTarget.dispatchEvent(new CustomEvent("ax-modal:close", { bubbles: true }))
    this.resetModal()
  }

  remove(event) {
    event.preventDefault()
    const wrapper = event.currentTarget.closest(".nested-fields, .ax-record-item")
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
    ;[this.typeSelectTarget, this.brokerSelectTarget, this.commissionTypeSelectTarget].forEach((select) => {
      select.value = ""

      if (select.tomselect) {
        select.tomselect.clear()
      }
    })
    this.commissionValueInputTarget.value = ""
  }
}
