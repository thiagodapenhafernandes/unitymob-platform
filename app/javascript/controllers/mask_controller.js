import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { type: String }

  connect() {
    this.mask()
    this.element.addEventListener('input', this.input.bind(this))
  }

  disconnect() {
    this.element.removeEventListener('input', this.input.bind(this))
  }

  input(event) {
    this.mask()
  }

  mask() {
    if (this.typeValue === "currency") {
      this.currencyMask()
    } else if (this.typeValue === "cep") {
      this.cepMask()
    } else if (this.typeValue === "cpf_cnpj") {
      this.cpfCnpjMask()
    }
  }

  currencyMask() {
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

    this.element.value = `${integerPart},${decimalPart}`
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
