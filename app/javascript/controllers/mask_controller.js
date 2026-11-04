import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { type: String }

  connect() {
    this.mask()
    this.boundInput = this.input.bind(this)
    this.element.addEventListener('input', this.boundInput)
  }

  disconnect() {
    this.element.removeEventListener('input', this.boundInput)
  }

  input(event) {
    this.mask(event)
  }

  mask(event) {
    if (this.typeValue === "currency") {
      this.currencyMask(event)
    } else if (this.typeValue === "cep") {
      this.cepMask()
    } else if (this.typeValue === "cpf_cnpj") {
      this.cpfCnpjMask()
    }
  }

  currencyMask(event) {
    const previousValue = this.element.value
    const selectionStart = this.element.selectionStart
    const selectionEnd = this.element.selectionEnd
    let raw = this.element.value.replace(/\D/g, "")
    if (raw === "") {
      this.element.value = ""
      return
    }

    let intVal = parseInt(raw)
    if (isNaN(intVal)) {
      this.element.value = ""
      return
    }

    raw = intVal.toString()

    // Pad with zeros if needed (e.g. "1" -> "001" -> 0,01)
    while (raw.length < 3) raw = "0" + raw

    let integerPart = raw.slice(0, raw.length - 2)
    let decimalPart = raw.slice(raw.length - 2)

    // Add dots to integer part
    integerPart = integerPart.replace(/\B(?=(\d{3})+(?!\d))/g, ".")

    const formatted = `${integerPart},${decimalPart}`
    if (formatted === previousValue) return

    this.element.value = formatted
    if (document.activeElement === this.element && selectionStart !== null && selectionEnd !== null) {
      const position = (offset) => {
        const digitsAfter = previousValue.slice(offset).replace(/\D/g, "").length
        let index = formatted.length
        let remaining = digitsAfter
        while (index > 0 && remaining > 0) {
          index -= 1
          if (/\d/.test(formatted[index])) remaining -= 1
        }
        if (event?.inputType !== "deleteContentForward") {
          while (index > 0 && /\D/.test(formatted[index - 1])) index -= 1
        }
        return index
      }
      this.element.setSelectionRange(position(selectionStart), position(selectionEnd))
    }
  }

  cepMask() {
    let value = this.element.value.replace(/\D/g, "").slice(0, 8)
    if (value.length > 5) {
      value = value.replace(/^(\d{5})(\d)/, "$1-$2")
    }
    this.element.value = value
  }

  cpfCnpjMask() {
    let value = this.element.value.replace(/\D/g, "")

    if (value.length <= 11) {
      value = value.slice(0, 11)
      if (value.length > 9) {
        value = value.replace(/^(\d{3})(\d{3})(\d{3})(\d{0,2}).*/, "$1.$2.$3-$4")
      } else if (value.length > 6) {
        value = value.replace(/^(\d{3})(\d{3})(\d{0,3}).*/, "$1.$2.$3")
      } else if (value.length > 3) {
        value = value.replace(/^(\d{3})(\d{0,3}).*/, "$1.$2")
      }
    } else {
      value = value.slice(0, 14)
      if (value.length > 12) {
        value = value.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{0,2}).*/, "$1.$2.$3/$4-$5")
      } else if (value.length > 8) {
        value = value.replace(/^(\d{2})(\d{3})(\d{3})(\d{0,4}).*/, "$1.$2.$3/$4")
      } else if (value.length > 5) {
        value = value.replace(/^(\d{2})(\d{3})(\d{0,3}).*/, "$1.$2.$3")
      } else if (value.length > 2) {
        value = value.replace(/^(\d{2})(\d{0,3}).*/, "$1.$2")
      }
    }

    this.element.value = value
  }
}
