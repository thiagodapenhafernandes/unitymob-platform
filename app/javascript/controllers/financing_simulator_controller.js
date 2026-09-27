import { Controller } from "@hotwired/stimulus"

// Simulador de financiamento (public_theme/components/financing_simulator).
// Juros efetivos anuais → mensais: i = (1 + a)^(1/12) − 1 (como os bancos informam).
//   Parcelas fixas (sistema francês/"Price"): P·i / (1 − (1 + i)^−n)
//   Parcelas decrescentes (SAC): amortização P/n; 1ª = P/n + P·i; última = P/n·(1 + i); juros = P·i·(n + 1)/2
// Renda sugerida: 1ª parcela do SAC até 30% da renda. Recalcula a cada ajuste e
// deixa a mensagem do botão de lead com os valores simulados.
export default class extends Controller {
  static targets = ["price", "down", "downLabel", "years", "rate", "sacFirst", "sacLast", "sacInterest",
    "pricePayment", "priceInterest", "financed", "downValue", "income", "warning", "cta"]
  static values = { propertyLabel: String }

  connect() {
    this.money = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL", maximumFractionDigits: 0 })
    this.calculate()
  }

  prevent(event) {
    event.preventDefault()
  }

  formatPrice() {
    const value = this.priceValue()
    this.priceTarget.value = value ? value.toLocaleString("pt-BR") : ""
  }

  calculate() {
    const price = this.priceValue()
    const downPercent = Number(this.downTarget.value) || 0
    const months = (Number(this.yearsTarget.value) || 30) * 12
    const annualRate = Math.max(Number(String(this.rateTarget.value).replace(",", ".")) || 0, 0)
    this.downLabelTarget.textContent = `${downPercent}%`
    this.warningTarget.hidden = downPercent >= 20

    const downValue = price * downPercent / 100
    const financed = price - downValue
    if (!(financed > 0)) return this.clear()

    const i = Math.pow(1 + annualRate / 100, 1 / 12) - 1
    const amortization = financed / months
    const sacFirst = amortization + financed * i
    const sacLast = amortization * (1 + i)
    const sacInterest = financed * i * (months + 1) / 2
    const pricePayment = i === 0 ? financed / months : financed * i / (1 - Math.pow(1 + i, -months))
    const priceInterest = pricePayment * months - financed

    this.write("sacFirst", sacFirst)
    this.write("sacLast", sacLast)
    this.write("sacInterest", sacInterest)
    this.write("pricePayment", pricePayment)
    this.write("priceInterest", priceInterest)
    this.write("financed", financed)
    this.write("downValue", downValue)
    this.write("income", sacFirst / 0.3)
    this.updateMessage({ price, downPercent, months, annualRate, sacFirst, pricePayment })
  }

  priceValue() {
    return Number(String(this.priceTarget.value).replace(/\D/g, "")) || 0
  }

  write(name, value) {
    this[`${name}Target`].textContent = this.money.format(value)
  }

  clear() {
    ["sacFirst", "sacLast", "sacInterest", "pricePayment", "priceInterest", "financed", "downValue", "income"]
      .forEach((name) => { this[`${name}Target`].textContent = "—" })
  }

  updateMessage({ price, downPercent, months, annualRate, sacFirst, pricePayment }) {
    const subject = this.propertyLabelValue ? ` do imóvel ${this.propertyLabelValue}` : ""
    this.ctaTarget.dataset.whatsappMessage =
      `Olá, simulei no site o financiamento${subject}: valor ${this.money.format(price)}, entrada de ${downPercent}%, ` +
      `${months / 12} anos, juros de ${annualRate.toLocaleString("pt-BR")}% a.a. ` +
      `(parcelas decrescentes a partir de ${this.money.format(sacFirst)}; parcelas fixas de ${this.money.format(pricePayment)}). ` +
      "Gostaria de falar com um especialista."
  }
}
