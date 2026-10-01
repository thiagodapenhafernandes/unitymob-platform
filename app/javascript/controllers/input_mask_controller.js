import { Controller } from "@hotwired/stimulus"

// Máscara de digitação definida no campo do formulário público.
//   0 = dígito · A = letra (maiúscula) · * = letra ou número · demais símbolos são fixos (ex.: 00-0000, (00) 00000-0000)
//   "money" = dinheiro: R$ 1.234,56 (tamanho variável)
// Os símbolos fixos nunca são letras/números, então dá para separar "o que o visitante digitou" do que a máscara inseriu.
const TOKENS = {
  "0": /\d/,
  A: /[A-Za-z]/,
  "*": /[A-Za-z0-9]/
}

export default class extends Controller {
  static values = { pattern: String }

  connect() {
    this.format()
  }

  format() {
    const value = this.element.value
    if (value === "") return

    this.element.value = this.patternValue === "money" ? this.money(value) : this.mask(value)
  }

  mask(raw) {
    const data = raw.replace(/[^0-9A-Za-z]/g, "")
    let output = ""
    let pendingFixed = ""
    let index = 0

    for (const symbol of this.patternValue) {
      const token = TOKENS[symbol]
      if (!token) {
        pendingFixed += symbol
        continue
      }

      // Pula o que não serve para esta posição (ex.: letra onde só cabe dígito).
      while (index < data.length && !token.test(data[index])) index += 1
      if (index >= data.length) break

      output += pendingFixed + (symbol === "A" ? data[index].toUpperCase() : data[index])
      pendingFixed = ""
      index += 1
    }
    return output
  }

  money(raw) {
    const digits = raw.replace(/\D/g, "").replace(/^0+(?=\d)/, "")
    if (digits === "") return ""

    const cents = digits.padStart(3, "0")
    const integer = cents.slice(0, -2).replace(/\B(?=(\d{3})+(?!\d))/g, ".")
    return `R$ ${integer},${cents.slice(-2)}`
  }
}
